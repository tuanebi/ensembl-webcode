=head1 LICENSE

Copyright [1999-2014] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

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

package EnsEMBL::Web::Component::Regulation::EvidenceSelector;

use strict;

use base qw(EnsEMBL::Web::Component::CloudMultiSelector EnsEMBL::Web::Component::Regulation);

use List::MoreUtils qw(uniq);

sub _init {
  my $self = shift;
 
  $self->SUPER::_init;
 
  $self->{'panel_type'}      = 'EvidenceSelector';
  $self->{'link_text'}       = 'Select evidence';
  $self->{'included_header'} = 'Selected {category} evidence';
  $self->{'excluded_header'} = 'Unselected {category} evidence';
  $self->{'url_param'}       = 'evidence';
  $self->{'rel'}             = 'modal_select_evidence';
}

sub content_ajax {
  my $self        = shift;
  my $hub         = $self->hub;
  my $object      = $self->object;
  my $params      = $hub->multi_params; 

  my $context       = $self->hub->param('context') || 200;
  my $object_slice  = $object->get_bound_context_slice($context);
     $object_slice  = $object_slice->invert if $object_slice->strand < 1;
  my $all_evidences = $self->all_evidences->{'all'};

  my %all_options = map { $_ => $_ } keys %$all_evidences;
  my @inc_options = grep { $all_evidences->{$_}{'on'} } keys %$all_evidences;
  my %inc_options;
  $inc_options{$inc_options[$_]} = $_+1 for(0..$#inc_options);
  my %evidence_categories = map { $_ => $all_evidences->{$_}{'group'} } keys %$all_evidences;
  $self->{'categories'} = [ uniq(values %evidence_categories) ];

  $self->{'all_options'}      = \%all_options;
  $self->{'included_options'} = \%inc_options;
  $self->{'param_mode'} = 'single';
  $self->{'category_map'} = \%evidence_categories;

  $self->SUPER::content_ajax;
}

1;
