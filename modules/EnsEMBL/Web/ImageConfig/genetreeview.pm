# $Id$

package EnsEMBL::Web::ImageConfig::genetreeview;

use strict;

use base qw(EnsEMBL::Web::ImageConfig);

sub init {
  my $self = shift;

  $self->set_parameters({
    title       => 'Gene tree panel',
    show_labels => 'no',  # show track names on left-hand side
    label_width => 113,   # width of labels on left-hand side
    bgcolor     => 'background1',
    bgcolour1   => 'background1',
    bgcolour2   => 'background1',
  });

  $self->create_menus(misc => 'General');

  $self->add_tracks('misc',
    [ 'genetree',        'Gene',   'genetree',        { on => 'on', strand => 'r' }],
    [ 'genetree_legend', 'Legend', 'genetree_legend', { on => 'on', strand => 'r' }],
  );
  
  $self->storable = 0;
}

1;

