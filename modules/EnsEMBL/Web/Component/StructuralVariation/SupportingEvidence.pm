
package EnsEMBL::Web::Component::StructuralVariation::SupportingEvidence;

use strict;

use base qw(EnsEMBL::Web::Component);

sub _init {
  my $self = shift;
  $self->cacheable(0);
  $self->ajaxable(1);
}

sub content {
  my $self = shift;
  my $object 				= $self->object;
	my $hub           = $self->hub;
	my $supporting_sv	= $object->supporting_sv;
  my $html          = $self->supporting_evidence_table($supporting_sv);
	return $html;
}


sub supporting_evidence_table {
  my $self     = shift;
  my $ssvs     = shift;
  my $hub      = $self->hub;
	my $object   = $self->object;
	my $title    = 'Supporting evidence';
	my $table_id = 'evidence';
	
  my $columns = [
		 { key => 'ssv',   sort => 'string',        title => 'Supporting evidence' },
		 { key => 'class', sort => 'string',        title => 'Allele type'         },
		 { key => 'pos',   sort => 'position_html', title => 'Chr:bp'              },
  ];

  my $rows = ();
  
	# Supporting evidences list
	if (scalar @{$ssvs}) {
		my $ssv_names = {};
		foreach my $ssv (@$ssvs){
			my $name = $ssv->name;
			$name =~ /(\d+)$/;
			my $ssv_nb = $1;
    	$ssv_names->{$1}{'name'}    = $name;
			$ssv_names->{$1}{'class'}   = $ssv->var_class;
			$ssv_names->{$1}{'SO_term'} = $ssv->class_SO_term;
			$ssv_names->{$1}{'sv'}      = $ssv->is_structural_variation;
		}
		foreach my $ssv_n (sort {$a <=> $b} (keys(%$ssv_names))) {
			my $name = $ssv_names->{$ssv_n}{'name'};
			my $loc;
			if ($ssv_names->{$ssv_n}{'sv'} ne '') {
				my $sv_obj = $ssv_names->{$ssv_n}{'sv'};
				
				# Name
				my $sv_link = $hub->url({
      									type   => 'StructuralVariation',
      									action => 'Summary',
      									sv     => $name,
											});
				$name = qq{<a href="$sv_link">$name</a>};
				
				# Location
        foreach my $svf (@{$sv_obj->get_all_StructuralVariationFeatures}) {
          my $chr_bp = $svf->seq_region_name . ':' . $svf->seq_region_start . '-' . $svf->seq_region_end;
          my $loc_url = $hub->url({
      		  type   => 'Location',
      		  action => 'View',
					  sv     => $name,
      		  r      => $chr_bp,
    		  });
				  $loc .= <br /> if ($loc);
				  $loc .= qq{<a href="$loc_url">$chr_bp</a>};
				}
    	}
			$loc = '-' if (!$loc);
	
			# Class + class colour
			my $colour = $object->get_class_colour($ssv_names->{$ssv_n}{'SO_term'});
			my $sv_class = '<table style="border-spacing:0px"><tr><td style="background-color:'.$colour.';width:5px"></td><td style="margin:0px;padding:0px">&nbsp;'.$ssv_names->{$ssv_n}{'class'}.'</td></tr></table>';
     	my %row = (
									ssv   => $name,
									class => $sv_class,
									pos   => $loc
      					);
				
      push @$rows, \%row;
		}
  	return $self->new_table($columns, $rows, { data_table => 1, sorting => [ 'location asc' ] })->render;
	}
}
1;
