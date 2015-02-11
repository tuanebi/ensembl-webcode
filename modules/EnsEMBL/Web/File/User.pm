=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

package EnsEMBL::Web::File::User;

use strict;

use Archive::Tar;

use parent qw(EnsEMBL::Web::File);

### Replacement for EnsEMBL::Web::TmpFile::Text, specifically for
### content generated by the user, either uploaded to the website
### or generated deliberately via a tool or export interface

### Path structure: /base_dir/YYYY-MM-DD/user_identifier/XXXXXXXXXXXXXXX_filename.ext

sub new {
### @constructor
  my ($class, %args) = @_;

  $args{'output_drivers'} = ['IO']; ## Always write to disk
  return $class->SUPER::new(%args);
}

### Wrappers around E::W::File::Utils::IO methods

sub preview {
### Get n lines of a file, e.g. for a web preview
### @param Integer - number of lines required (default is 10)
### @return Arrayref (n lines of file)
  my ($self, $limit) = @_;
  my $result = {};

  foreach (@{$self->{'output_drivers'}}) {
    my $method = 'EnsEMBL::Web::File::Utils::'.$_.'::preview_file';
    my $args = {
                'hub'     => $self->hub,
                'nice'    => 1,
                'limit'   => $limit,
                };

    eval {
      no strict 'refs';
      $result = &$method($self, $args);
    };
    last unless $result->{'error'};
  }
  return $result;
}

sub write_line {
### Write (append) a single line to a file
### @param String
### @return Hashref
  my ($self, $line) = @_;

  my $result = {};

  foreach (@{$self->{'output_drivers'}}) {
    my $method = 'EnsEMBL::Web::File::Utils::'.$_.'::append_lines';
    my $args = {
                'hub'     => $self->hub,
                'nice'    => 1,
                'lines'   => [$line],
                };

    eval {
      no strict 'refs';
      $result = &$method($self, $args);
    };
    last unless $result->{'error'};
  }
  return $result;
}

sub upload {
### Upload data from a form and save it to a file
  my ($self, %args) = @_;
  my $hub       = $self->hub;

  my ($method)  = $args{'method'} || grep $hub->param($_), qw(file url text);
  my $type      = $args{'type'};

  my @orig_path = split '/', $hub->param($method);
  my $filename  = $orig_path[-1];
  my $name      = $hub->param('name');
  my $f_param   = $hub->param('format');
  my ($error, $format, $full_ext);

  ## Need the filename (for handling zipped files)
  unless ($name) {
    if ($method eq 'text') {
      $args{'name'} = 'Data';
    } else {
      my @orig_path = split('/', $hub->param($method));
      $args{'name'} = $orig_path[-1];
    }
  }

  ## Some uploads shouldn't be viewable as tracks, e.g. assembly converter input
  my $no_attach = $type eq 'no_attach' ? 1 : 0;

  ## Has the user specified a format?
  if ($f_param) {
    $format = $f_param;
  } elsif ($method ne 'text') {
    ## Try to guess the format from the extension
    my @parts       = split('\.', $filename);
    my $ext         = $parts[-1] =~ /gz|zip/i ? $parts[-2] : $parts[-1];
    my $format_info = $hub->species_defs->multi_val('DATA_FORMAT_INFO');
    my $extensions;

    foreach (@{$hub->species_defs->multi_val('UPLOAD_FILE_FORMATS')}) {
      $format = uc $ext if $format_info->{lc($_)}{'ext'} =~ /$ext/i;
    }
  }
 
  $args{'timestamp_name'}  = 1;

  if ($method eq 'url') {
    $args{'file'}          = $hub->param($method);
    $args{'upload'}        = 'url';
  }
  elsif ($method eq 'text') {
    ## Get content straight from CGI, since there's no input file
    my $text = $hub->param('text');
    if ($type eq 'coords') {
      $text =~ s/\s/\n/g;
    }
    $args{'content'} = $text;
  }
  else {
    $args{'file'}   = $hub->input->tmpFileName($hub->param($method));
    $args{'upload'} = 'cgi';
  }

  ## Now we know where the data is coming from, initialise the object and read the data
  $self->init(%args);
  my $result = $self->read;

  ## Add upload to session
  if ($result->{'error'}) {
    $error = $result->{'error'};
  }
  else {
    my $response = $self->write($result->{'content'});

    if ($response->{'success'}) {
      my $session = $hub->session;
      my $md5     = $self->md5($result->{'content'});
      my $code    = join '_', $md5, $session->session_id;
      my $format  = $hub->param('format');
      $format     = 'BED' if $format =~ /bedgraph/i;
      my %inputs  = map $_->[1] ? @$_ : (), map [ $_, $hub->param($_) ], qw(filetype ftype style assembly nonpositional assembly);

      $inputs{'format'}    = $format if $format;
      my $species = $hub->param('species') || $hub->species;

      ## Attach data species to session
      ## N.B. Use 'write' locations, since uploads are read from the
      ## system's CGI directory
      my $data = $session->add_data(
                                    type      => 'upload',
                                    file      => $self->write_location,
                                    filesize  => length($result->{'content'}),
                                    code      => $code,
                                    md5       => $md5,
                                    name      => $name,
                                    species   => $species,
                                    format    => $format,
                                    no_attach => $no_attach,
                                    timestamp => time,
                                    assembly  => $hub->species_defs->get_config($species, 'ASSEMBLY_VERSION'),
                                    %inputs
                                    );

      $session->configure_user_data('upload', $data);
    }
    else {
      $error = $response->{'error'};
    }
  }
  return $error;
}

sub write_tarball {
### Write an array of file contents to disk as a tarball
### N.B. Unlike other methods, this does not use the drivers
### TODO - this method has not been tested!
### @param content ArrayRef
### @param use_short_names Boolean
### @return HashRef
  my ($self, $content, $use_short_names) = @_;
  my $result = {};

  my $tar = Archive::Tar->new;
  foreach (@$content) {
    $tar->add_data(
      ($use_short_names ? $_->{'shortname'} : $_->{'filename'}), 
      $_->{'content'},
    );
  }

  my %compression_flags = (
                          'gz' => 'COMPRESS_GZIP',
                          'bz' => 'COMPRESS_BZIP',
                          );


  $tar->write($self->file_name, $compression_flags{$self->compression}, $self->base_path);

  return $result;
}

1;

