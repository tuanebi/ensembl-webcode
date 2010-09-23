package EnsEMBL::Web::ViewConfig::Gene::Matches;

use strict;

use EnsEMBL::Web::Constants;

sub init {
my $view_config = shift;
my $help  = shift;
  
  $view_config->storable = 1;
  $view_config->nav_tree = 1;
  my %defaults;
  my %defaults_off;
  my @xref_types = get_xref_types();  
  my @default_on = ('Ensembl Human Transcript' , 'HGNC (curated)', 'HGNC (automatic)', 'EntrezGene', 'CCDS', 'RefSeq RNA', 'UniProtKB/ Swiss-Prot', 'RefSeq peptide', 'RefSeq DNA', 'RFAM', 'miRBase', 'Vega transcript', 'MIM disease');
  
  foreach (@xref_types){
    my $default_enabled=0;
    for( my $i=0; $i< scalar(@default_on) && !$default_enabled; $i++){
      $default_enabled = $_->{'name'} eq $default_on[$i];
    }
    if($default_enabled){
      $defaults{$_->{'name'}}='yes';
    }else{
      $defaults_off{$_->{'name'}}=undef;    
    }
  }
  $view_config->_set_defaults(%defaults);
}

sub form {
  my ($view_config, $object) = @_;
  my @xref_types = get_xref_types();

  @xref_types = sort {sort_by_default_on($b) <=> sort_by_default_on($a)} @xref_types;

  foreach (@xref_types){
     my $external_ref_type_chec_box = {
      'type'  => 'CheckBox',
      'select' => 'select',
      'name'   => $_->{'name'},
      'label'  => $_->{'name'},
      'value' => 'yes'
    };     
    $view_config->add_form_element($external_ref_type_chec_box);
  }
}

sub get_xref_types {
  my $species= $ENV{'ENSEMBL_SPECIES'};
  my $SPECIES_DEFS = EnsEMBL::Web::SpeciesDefs->new();
  
  my $xref_types_string = $SPECIES_DEFS->get_config($species, 'XREF_TYPES');
  my @xref_types;
  foreach(split(/,/, $xref_types_string)){
    my @type_priorities = split(/=/,$_);
    my $xref_type;
	  $xref_type->{'name'}=@type_priorities[0];
	  $xref_type->{'priority'}=@type_priorities[1];
	  push(@xref_types,$xref_type)
  }
  return @xref_types;
}

sub sort_by_default_on{
  my $value=shift;
  my @default_on = ('Ensembl Human Transcript' , 'HGNC (curated)', 'HGNC (automatic)', 'EntrezGene', 'CCDS', 'RefSeq RNA', 'UniProtKB/ Swiss-Prot', 'RefSeq peptide', 'RefSeq DNA', 'RFAM', 'miRBase', 'Vega transcript', 'MIM disease');  
  my $return=0;
  
  for (my $i=0; $i< scalar(@default_on) && !$return; $i++){
    $return = ($default_on[$i] eq $value->{'name'});
  }
  return $return;
}
1;
