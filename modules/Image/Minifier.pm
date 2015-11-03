package Image::Minifier;

use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(minify generate_sprites data_url);

our $VERSION = '0.01';

use List::Util qw(max);
use Digest::MD5 qw(md5_hex);
use YAML qw(LoadFile);
use MIME::Base64;
use SiteDefs;
use EnsEMBL::Web::Utils::FileHandler qw(file_get_contents);
use EnsEMBL::Web::Utils::PluginInspector qw(get_all_plugins);

my $SPACE_PAD = 3;
my $PAGE_WIDTH = 1000;

my @OK_CLASSES = qw(bordered float-right ebi-logo float-left sanger-logo
  search_image homepage-link _ht overlay_close screen_hide_inline);
my @OK_STYLES = qw(
  vertical-align position top left bottom right float
  margin margin-left margin-top margin-bottom margin-right
);
my @OK_ATTRS = qw(onClick);

sub hex_for {
  return substr(md5_hex($_[0]),0,16);
}

sub images_size {
  my ($filenames) = @_;

  my %dirs;
  foreach my $fn (@$filenames) {
    my @path = split('/',$fn);
    my $fn = pop @path;
    push @{$dirs{join('/',@path)}||=[]},$fn;
  }

  my %out;
  foreach my $dir (keys %dirs) {
    my @batches = ([]);
    foreach my $f (@{$dirs{$dir}}) {
      push @{$batches[-1]},$f;
      push @batches,[] if @{$batches[-1]} > 50;
    }
    foreach my $b (@batches) {
      my $all = join(' ',map { "$dir/$_" } @$b);
      my $size = qx(identify -format "%f~%w~%h~%n\n" $all 2>/dev/null);
      foreach my $line (split("\n",$size)) {
        my ($f,$w,$h,$n) = split('~',$line);
        next unless $n == 1; # Ignore animations
        $out{"$dir/$f"} = [$w,$h];
      }
    }
  }
  return \%out;
}

sub filter_images {
  my ($in,$type,$page) = @_;

  my @out;
  my $sizes = images_size([map { $_->{'file'} } @$in]);
  foreach my $f (@$in) {
    my ($w,$h) = @{$sizes->{$f->{'file'}}||[0,0]};
    next unless $w and $h;
    next if $w > 300 or $h > 100;
    next if $w > 100 and $type eq 'jpg';
    $f->{'w'} = $w;
    $f->{'h'} = $h;
    push @out,$f;
  } 
  return \@out;
}

sub find_exceptions {
  my ($conf,$file) = @_;

  my %out;
  foreach my $e (@$conf) {
    next unless $file =~ /^$e->{'pattern'}$/;
    foreach my $k (keys %$e) {
      next if $k eq 'pattern';
      $out{$k} = { %{$out{$k}||{}}, %{$e->{$k}} };
    }
  }
  return \%out;
}

sub css_rule {
  my ($h,$f,$x,$y,$pw,$ph) = @_;

  return "";
  my %payload = (
    height => "$f->{'h'}px",
    width => "$f->{'w'}px",
    "background-position" => "-${x}px -${y}px",
  );
  my @payload;
  foreach my $k (keys %payload) {
    my $p = "$k: $payload{$k};";
    push @payload,$p;
  }
  my $payload = join(' ',@payload);
  return "html img.autosprite.autosprite-$h { $payload }\n";
}

sub build_conf {
  my @conf;
  foreach my $plugin (@{get_all_plugins()}) {
    my $filename = "$plugin->{'path'}/conf/images.yaml";
    next unless -e $filename;
    my $here = LoadFile($filename);
    foreach my $entry (@{$here->{'properties'}||[]}) {
      foreach my $pattern (@{$entry->{'patterns'}||[]}) {
        my %properties = %$entry;
        delete $properties{'patterns'};
        push @conf,{
          pattern => $pattern,
          %properties
        };
      }
    }
  }
  return \@conf;
}

sub minify {
  my ($species_defs,$paths) = @_;

  my $conf = build_conf();
  open(LOG,'>>',$SiteDefs::ENSEMBL_LOGDIR.'/image-minify.log');
  my $title = sprintf("Sprite page generation at %s\n",scalar localtime);
  $title .= ('=' x length $title)."\n\n";
  print LOG $title;
  my $root = $species_defs->ENSEMBL_DOCROOT.'/'.$species_defs->ENSEMBL_MINIFIED_FILES_PATH;
  my $css = '';
  # Process each file
  my @files;
  foreach my $row (split("\n",$paths)) {
    chomp $row;
    my ($url,$file) = split('\t',$row);
    next unless $file;
    push @files,$file;
  }
  my %files;
  foreach my $row (split("\n",$paths)) {
    chomp $row;
    my ($url,$file) = split('\t',$row);
    next unless $url and $file and -e $file;
    $url =~ s!^/\./!/!;
    my $type = [ split('\.',$file) ]->[-1];
    next unless $type;
    my $exc = find_exceptions($conf,$file);
    next if $exc->{'action'} and $exc->{'action'}{'exclude'};

    $type = 'jpg' if $type eq 'jpeg';
    next if $file =~ m!/minified/!;
    my $outtype = $type;
    if($exc->{'transcode'} and $exc->{'transcode'}{$type}) {
      $outtype = $exc->{'transcode'}{$type};
    }
    $outtype = 'png' if $outtype eq 'gif';
    my $page = $exc->{'page'}{'name'} || 'default';
    print LOG "$type/$outtype/$page ".hex_for($url)." => $url\n";
    $files{$outtype} ||= {};
    $files{$outtype}{$page} ||= [];
    push @{$files{$outtype}{$page}},{
      url => $url,
      file => $file,
      nudge => $exc->{'action'}{'nudge'},
      pad => $exc->{'action'}{'pad'}||0
    };
  }
  foreach my $type (keys %files) {
    foreach my $page (keys %{$files{$type}}) {
      $files{$type}{$page} = filter_images($files{$type}{$page},$type,$page);
    }
  }
  my %sprites;
  foreach my $type (keys %files) {
    foreach my $page (keys %{$files{$type}}) {
      print LOG "\nBuilding sprite page for $page/$type\n\n";
      my ($w,$h) = ($PAGE_WIDTH,0);
      my ($xo,$yo) = (0,0);
      my $maxy = 0;
      my @files = sort { $a->{'h'} <=> $b->{'h'} } @{$files{$type}{$page}};
      foreach my $f (@files) {
        my $hspace = $f->{'w'} + 2*$SPACE_PAD + 2*$f->{'pad'};
        if($xo+$hspace > $w) {
          $xo = $SPACE_PAD;
          $yo += $maxy + 2*$SPACE_PAD;
          $h += $maxy + 2*$SPACE_PAD;
          $maxy = 0;
          print LOG "NEW ROW\n";
        }
        $f->{'x'} = $xo + $SPACE_PAD + $f->{'pad'};
        $f->{'y'} = $yo + $SPACE_PAD + $f->{'pad'};
        $f->{'hash'} = hex_for($f->{'url'});
        $f->{'pk'} = "$page-$type";
        print LOG "  $f->{'hash'} $f->{'url'}\n";
        $xo += $f->{'w'} + 2*$SPACE_PAD + 2*$f->{'pad'};
        $maxy = max($maxy,$f->{'h'}+2*$f->{'pad'});
      }
      $h += $maxy + 2*$SPACE_PAD;
      next unless $h;
      print LOG "Sprite page for $page/$type measures ${w}x$h\n";
      my $tmp = "$root/x-$page.tmp.$type";
      my $tmp2 = "$root/x-$page.tmp2.$type";
      my $bgd = "xc:none";
      $bgd = "xc:white" if $type eq 'jpg';
      print LOG qx(convert -size ${w}x$h $bgd $tmp 2>&1);
      my @batches = ([]);
      foreach my $f (@files) {
        push @{$batches[-1]},$f;
        push @batches,[] if @{$batches[-1]} > 50;
      }
      foreach my $batch (@batches) {
        my $cmd = qq(convert $tmp );
        foreach my $f (@$batch) {
          $cmd .= qq($f->{'file'} -geometry +$f->{'x'}+$f->{'y'} -composite );
        }
        $cmd .= qq( $tmp);
        print LOG qx($cmd 2>&1);
      }
      if($type eq 'png') {
        print LOG qx(pngcrush $tmp $tmp2 2>&1);
      } else {
        rename $tmp,$tmp2;
      }
      unlink $tmp;
      my $md5 = Digest::MD5->new;
      open(my $fh,$tmp2) or die "Cannot read sprite page";
      $md5->addfile($fh);
      close $fh;
      my $hex = $md5->hexdigest;
      my $fn = "$root/$hex.$type";
      rename $tmp2,$fn;
      my $url = "/minified/$hex.$type";
      $css .= qq(.autosprite-src-$page-$type { background-image: url($url) });
      foreach my $f (@{$files{$type}{$page}}) {
        my $nudge = $f->{'nudge'}||[0,0];
        my $x = $f->{'x'} - $nudge->[0];
        my $y = $f->{'y'} - $nudge->[1];
        $css .= css_rule($f->{'hash'},$f,$x,$y,$w,$h);
        $sprites{$f->{'hash'}} = [$f->{'w'},$f->{'h'},$x,$y,$w,$h,$f->{'pk'}];
      }
    }
  }
  $species_defs->set_config('ENSEMBL_SPRITES',\%sprites);
  $species_defs->store;

  close LOG;
  return $css;
}

# XXX prune warns

sub maybe_generate_sprite {
  my ($valid,$tag) = @_;

  # Build attributes
  my $attrs = $tag;
  $attrs =~ s!/\s*$!!;
  my $num = 0;
  my %attrs;
  while($num<20 and $attrs =~ s/\s*(\w+)=(['"])//) {
    my ($key,$quot) = ($1,$2);
    last unless $attrs =~ s/^([^$quot]*)$quot//;
    $attrs{$key} = $1;
    $num++;
  }
  if($attrs =~ /\S/ or !$attrs{'src'}) {
    warn "skipping weird tag: $tag\n";
    return "<img$tag>";
  }
  if($attrs{'src'} =~ m!^(https?:)?//!) {
    my $class = $attrs{'class'} || '';
    return qq(<div class="_afterimage $class" data-url="$attrs{'src'}"></div>);
  }
  my $fn = $attrs{'src'};
  $fn =~ s!//!/!g;
  #warn "File $fn\n";
  my $hash = hex_for($fn);
  if(!$valid->{$hash}) {
    #warn "skipping unknown tag: $tag ($hash)\n";
    return "<img$tag>";
  }
  delete $attrs{'src'};
  my $text = "";
  my $more_attrs = '';
  $more_attrs .= qq(alt="$attrs{'alt'}") if $attrs{'alt'};
  $more_attrs .= qq(title="$attrs{'title'}") if $attrs{'title'};
  delete $attrs{'alt'};
  delete $attrs{'title'};
  my $width = $attrs{'width'} || $valid->{$hash}[0];
  my $height = $attrs{'height'} || $valid->{$hash}[1];
  delete $attrs{'width'};
  delete $attrs{'height'};
  my @classes = split(' ',$attrs{'class'}||'');
  my %ok_classes = map { $_ => 1 } @OK_CLASSES;
  my @not_ok_classes = grep { !exists $ok_classes{$_} } @classes;
  if(@not_ok_classes) {
    #warn "unhandled class: ".join(', ',@not_ok_classes)."\n";
    return "<img$tag>";
  }
  delete $attrs{'class'};
  my %styles;
  my ($nudgex,$nudgey) = (0,0);
  my @style = grep { /\S/ } split(';',$attrs{'style'}||'');
  foreach my $s (@style) {
    my ($k,$v) = split(':',$s,2);
    $k =~ s/\s//g;
    if($k eq 'width' and $v =~ s/px//) {
      $width = 0+$v;
    } elsif($k eq 'height' and $v =~ s/px//) {
      $height = 0+$v;
    } elsif(grep { $_ eq $k } @OK_STYLES) {
      $styles{$k}=$v;
    } else {
      #warn "unhandled style: $k : $tag\n";
      return "<img$tag>";
    }
  } 
  delete $attrs{'style'};
  foreach my $c (@OK_ATTRS) {
    if($attrs{$c}) {
      $more_attrs .= qq($c="$attrs{$c}");
      delete $attrs{$c};
      $styles{'cursor'} = 'pointer' if $c =~ /^on/;
    }
  }
  if(%attrs) {
    #warn "skipping unhandled atttributes: ".join(', ',keys %attrs)." : $tag\n";
    return "<img$tag>";
  }
  #warn "replacing with sprite $hash\n";
  my ($s_w,$s_h,$s_x,$s_y,$p_w,$p_h,$s_t) = @{$valid->{$hash}};

  if($width != $s_w or $height != $s_h or 1) {
    my $wscale = $s_w / $width;
    my $hscale = $s_h / $height;
    my $wsize = $p_w / $wscale;
    my $hsize = $p_h / $hscale;
    my $xoff = $s_x / $wscale;
    my $yoff = $s_y / $hscale;
    %styles = (
      'background-position' => "-${xoff}px -${yoff}px",
      'background-size' => "${wsize}px ${hsize}px",
      width => "${width}px",
      height => "${height}px",
      %styles
    );
  }
  my $style = '';
  $style = 'style="'.join(';',map { "$_: $styles{$_}" } keys %styles).'"' if %styles;
  my $classes = '';
  $classes = join(' ',@classes) if @classes;
  return qq(<img src='data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg"/>' class="autosprite-src-$s_t $classes" $style $more_attrs/>);
  return qq(<img src='data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg"/>' class="autosprite-src-$s_t autosprite-$hash $classes" $style $more_attrs/>);
}

sub generate_sprites {
  my ($species_defs,$content) = @_;

  warn "EDI = $SiteDefs::ENSEMBL_DEBUG_IMAGES\n";
  return $content if $SiteDefs::ENSEMBL_DEBUG_IMAGES;
  my $root = $species_defs->ENSEMBL_DOCROOT.'/'.$species_defs->ENSEMBL_MINIFIED_FILES_PATH;
  my $valid_sprites = $species_defs->get_config(undef,'ENSEMBL_SPRITES');

  $content =~ s/<img([^>]+)>/maybe_generate_sprite($valid_sprites,$1)/ge;
  return $content;
}

sub find_file {
  my ($sd,$url) = @_;

  foreach my $htdocs_dir (grep { !m/biomart/ && -d $_ } reverse @{$sd->ENSEMBL_HTDOCS_DIRS || []}) {
    my $f = "$htdocs_dir/$url";
    return $f if -e $f;
  }
  return undef;
}

sub data_url_convert {
  my ($key,$prefix,$suffix,$sd,$url) = @_;

  open(LOG,'>>',$SiteDefs::ENSEMBL_LOGDIR.'/image-minify.log');
  $url =~ s/^"(.*)"$/$1/;
  $url =~ s/^'(.*)'$/$1/;
  return undef unless $url =~ m!^/!;
  my $file = find_file($sd,$url);
  return undef unless $file and -e $file;
  my $tmp = "$file.tmp";
  if($file =~ /.png$/) {
    print LOG qx(pngcrush $file $tmp 2>&1);
  } else {
    print LOG qx(convert $file $tmp 2>&1);
  }
  return undef unless -e $tmp;
  my $data = file_get_contents($tmp);
  unlink $tmp;
  warn "$url ".length($data)."\n";
  return undef if length($data) > 2048;
  my $base64 = encode_base64($data,'');
  my $mime = $url;
  $mime =~ s!^.*\.!!;
  return undef unless $mime eq 'gif' or $mime eq 'png';
  $mime = "image/$mime";
  close LOG;
  return "$key: $prefix url(data:$mime;base64,$base64) $suffix;";
}

sub data_url_convert_try {
  my ($key,$prefix,$suffix,$sd,$url) = @_;

  my $out = data_url_convert($key,$prefix,$suffix,$sd,$url);
  return "$key: $prefix url($url) $suffix;" unless $out;
  return $out;
} 

sub data_url {
  my ($species_defs,$content) = @_;

  return $content if $SiteDefs::ENSEMBL_DEBUG_IMAGES;
  my $root = $species_defs->ENSEMBL_DOCROOT;
  $content =~ s!background-image:\s*url\(([^\)]+)\);?!data_url_convert_try('background-image','','',$species_defs,$1)!ge;
  $content =~ s!list-style-image:\s*url\(([^\)]+)\);?!data_url_convert_try('list-style-image','','',$species_defs,$1)!ge;
  $content =~ s!background:([^;}]*\s*)url\(([^\)]+)\)(\s*[^;}]*);?!data_url_convert_try('background',$1,$3,$species_defs,$2)!ge;
  return $content;
}

1;
