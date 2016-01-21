package EnsEMBL::Web::Query::Generic::GlyphSet;

use strict;
use warnings;

use base qw(EnsEMBL::Web::Query::Generic::Base);

use List::Util qw(min max);

sub slice2sr {
  my ($self,$slice,$s,$e) = @_;

  return $slice->strand < 0 ?
    ($slice->end   - $e + 1, $slice->end   - $s + 1) : 
    ($slice->start + $s - 1, $slice->start + $e - 1);
}

sub post_process_href {
  my ($self,$glyphset,$key,$ff) = @_; 

  foreach my $f (@$ff) {
    $f->{$key} = $glyphset->_url($f->{$key}) if $f->{$key};
  }
}

sub post_process_colour {
  my ($self,$glyphset,$key,$ff,$default) = @_;

  foreach my $f (@$ff) {
    $f->{$key} = $glyphset->my_colour($f->{$key}) || $default;
  }
}

sub post_process_start {
  my ($self,$glyphset,$key,$ff) = @_;

  my @out;
  foreach my $f (@$ff) {
    $f->{$key} -= $glyphset->{'container'}->start+1;
    next if $f->{$key} > $glyphset->{'container'}->length;
    $f->{$key} = max($f->{$key},0);
    push @out,$f;
  }
  @$ff = @out;
}

sub post_generate_start {
  my ($self,$glyphset,$key,$ff,$params,$slice) = @_;

  foreach my $f (@$ff) {
    $f->{$key} += $params->{$slice}->start-1;
  }
}

sub post_process_end {
  my ($self,$glyphset,$key,$ff) = @_;

  my @out;
  foreach my $f (@$ff) {
    $f->{$key} -= $glyphset->{'container'}->start+1;
    next if $f->{$key} < 0;
    $f->{$key} = min($glyphset->{'container'}->length,$f->{$key});
    push @out,$f;
  }
  @$ff = @out;
}

sub post_generate_end {
  my ($self,$glyphset,$key,$ff,$params,$slice) = @_;

  foreach my $f (@$ff) {
    $f->{$key} += $params->{$slice}->start-1;
  }
}

sub pre_process_slice {
  my ($self,$glyphset,$key,$ff) = @_;

  $ff->{$key} = $ff->{$key}->name;
}

sub pre_generate_slice {
  my ($self,$glyphset,$key,$ff) = @_;

  my $hub = $glyphset->{'config'}{'hub'};
  $ff->{$key} = $self->source('Adaptors')->slice_by_name($hub->species,$ff->{$key});
}

sub _split_slice {
  my ($self,$slice,$rsize) = @_;

  return [undef] unless defined $slice;
  my @out;
  my $rstart = int($slice->start/$rsize)*$rsize;
  while($rstart <= $slice->end) {
    push @out,Bio::EnsEMBL::Slice->new(
      -coord_system => $slice->coord_system,
      -start => $rstart,
      -end => $rstart + $rsize,
      -strand => $slice->strand,
      -seq_region_name => $slice->seq_region_name,
      -adaptor => $slice->adaptor
    );
    $rstart += $rsize;
  }
  return \@out;
}


sub blockify_ourslice {
  my ($self,$glyphset,$key,$ff,$rsize) = @_;

  my @out;
  foreach my $r (@$ff) {
    foreach my $slice (@{$self->_split_slice($r->{$key},$rsize||10_000)}) {
      my %new_r = %$r;
      $new_r{$key} = $slice;
      push @out,\%new_r;
    }
  }
  @$ff = @out;
}

1;