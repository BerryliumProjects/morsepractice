use warnings;
use strict;

package DialogFields;

sub init {
   my ($class, $w, $callback, $mincolwidth) = @_;
   
   my $dfref = {};
   bless $dfref, $class;

   $dfref->{controls} = {};
   $dfref->{entries} = {};
   $dfref->{attr} = {}; # attributes
   $dfref->{g} = $w->Frame->pack; # frame for grid containing controls with labels at left

   if ($mincolwidth) {
     $dfref->{g}->gridColumnconfigure(1, '-minsize' => $mincolwidth);
     $dfref->{g}->gridColumnconfigure(2, '-minsize' => $mincolwidth);
   }

   $dfref->{row} = 0; # row counter for g
   $dfref->{b} = undef; # frame for grid containing buttons - define later
   $dfref->{col} = 0; # column counter for b
   $dfref->{w} = $w;
   $dfref->{callback} = $callback;

   return $dfref;

}

sub entries {
   my $self = shift;
   return $self->{entries};
}

sub addEntryField {
   my $self = shift;
   my $ctllabel = shift;
   my $ctlvar = shift;
   my $width = shift;
   my $initvalue = shift;
   my $shortcutaltkey = shift;
   my $onfocusout = shift;
   my $attributes = shift;

   (defined $attributes) or ($attributes = '');

   $self->{entries}->{$ctlvar} = $initvalue;

   my $row = ++($self->{row});

   my $labelctl = $self->{g}->Label(-text=>$ctllabel, -font=>'msgbox');
   $labelctl->grid(-row=>$row, -column=>1, -sticky=>'w');

   my $entryctl = $self->{g}->Entry(-width=>$width, -font=>'msgbox', -textvariable=>\$self->{entries}->{$ctlvar});
   $entryctl->grid(-row=>$row, -column=>2, -sticky=>'w');
   $self->{controls}->{$ctlvar} = $entryctl;

   if (defined $shortcutaltkey) {
      $self->{w}->bind("<Alt-KeyPress-$shortcutaltkey>", [$entryctl => 'focus']);
      my $underlinepos = index(lc($ctllabel),$shortcutaltkey);

      if ($underlinepos >= 0) {
         $labelctl->configure(-underline=>$underlinepos);
      }
   }

   if (defined $onfocusout) {
      $entryctl->bind('<FocusOut>', $onfocusout);
   }

   if ($attributes =~ /locked/) {
      $entryctl->configure(-state=>'disabled');
   }

   $self->{attr}->{$ctlvar} = "entry $attributes ";

   return $entryctl;
}

sub addCheckbuttonField {
   my $self = shift;
   my $ctllabel = shift;
   my $ctlvar = shift;
   my $initvalue = shift;
   my $shortcutaltkey = shift;
   my $command = shift;
   my $attributes = shift;

   (defined $attributes) or ($attributes = '');

   $self->{entries}->{$ctlvar} = $initvalue;

   my $row = ++($self->{row});

   my $labelctl = $self->{g}->Label(-text=>$ctllabel, -font=>'msgbox');
   $labelctl->grid(-row=>$row, -column=>1, -sticky=>'w');

   my $entryctl = $self->{g}->Checkbutton(-font=>'msgbox', -variable=>\$self->{entries}->{$ctlvar});
   $entryctl->grid(-row=>$row, -column=>1, -sticky=>'e');
   $self->{controls}->{$ctlvar} = $entryctl;

   if (defined $shortcutaltkey) {
      $self->{w}->bind("<Alt-KeyPress-$shortcutaltkey>", [$entryctl => 'focus']);
      my $underlinepos = index(lc($ctllabel),$shortcutaltkey);

      if ($underlinepos >= 0) {
         $labelctl->configure(-underline=>$underlinepos);
      }
   }

   $entryctl->bind('<ButtonPress-1>', [$entryctl => 'focus']);

   if (defined $command) {
      $entryctl->configure(-command=>$command);
   }

   if ($attributes =~ /locked/) {
      $entryctl->configure(-state=>'disabled');
   }

   $self->{attr}->{$ctlvar} = "checkbutton $attributes ";

   return $entryctl;
}


sub addCheckbuttonField2 {
   my $self = shift;
   my $ctllabel = shift;
   my $ctlvar = shift;
   my $initvalue = shift;
   my $shortcutaltkey = shift;
   my $command = shift;
   my $attributes = shift;

   (defined $attributes) or ($attributes = '');

   $self->{entries}->{$ctlvar} = $initvalue;

   my $row = $self->{row}; # same row as left check button field

   my $labelctl = $self->{g}->Label(-text=>$ctllabel, -font=>'msgbox');
   $labelctl->grid(-row=>$row, -column=>2, -sticky=>'w');

   my $entryctl = $self->{g}->Checkbutton(-font=>'msgbox', -variable=>\$self->{entries}->{$ctlvar});
   $entryctl->grid(-row=>$row, -column=>2, -sticky=>'e');
   $self->{controls}->{$ctlvar} = $entryctl;

   if (defined $shortcutaltkey) {
      $self->{w}->bind("<Alt-KeyPress-$shortcutaltkey>", [$entryctl => 'focus']);
      my $underlinepos = index(lc($ctllabel),$shortcutaltkey);

      if ($underlinepos >= 0) {
         $labelctl->configure(-underline=>$underlinepos);
      }
   }

   $entryctl->bind('<ButtonPress-1>', [$entryctl => 'focus']);

   if (defined $command) {
      $entryctl->configure(-command=>$command);
   }

   if ($attributes =~ /locked/) {
      $entryctl->configure(-state=>'disabled');
   }

   $self->{attr}->{$ctlvar} = "checkbutton $attributes ";

   return $entryctl;
}

sub addWideTextField {
   my $self = shift;
   my $ctllabel = shift;
   my $ctlvar = shift;
   my $height = shift;
   my $width = shift;
   my $initvalue = shift;
   my $shortcutaltkey = shift;
   my $onfocusout = shift;
   my $attributes = shift;

   (defined $attributes) or ($attributes = '');

   $self->{entries}->{$ctlvar} = $initvalue;

   # Wide fields don't fit into the 2 column grid

#   my $row = ++($self->{row});

   my $labelctl;
 
   if (defined $ctllabel) {
      $labelctl = $self->{w}->Label(-text=>$ctllabel, -font=>'msgbox')->pack;
   }

   my $entryctl = $self->{w}->Text(-height=>$height, -font=>'msgbox', -spacing2=>2, -spacing3=>2, -width=>$width)->pack;

   $self->{controls}->{$ctlvar} = $entryctl;

   $entryctl->Contents($initvalue);

   if (defined $shortcutaltkey and defined $ctllabel) {
      $self->{w}->bind("<Alt-KeyPress-$shortcutaltkey>", [$entryctl => 'focus']);
      my $underlinepos = index(lc($ctllabel),$shortcutaltkey);

      if ($underlinepos >= 0) {
         $labelctl->configure(-underline=>$underlinepos);
      }
   }

   if (defined $onfocusout) {
      $entryctl->bind('<FocusOut>', $onfocusout);
   }   

   if ($attributes =~ /locked/) {
      $entryctl->configure(-state=>'disabled');
   }

   $self->{attr}->{$ctlvar} = "wide text $attributes ";

   return $entryctl;
}

sub addButtonField {
   my $self = shift;
   my $ctllabel = shift;
   my $ctlvar = shift;
   my $shortcutaltkey = shift;
   my $command = shift; # overrides callback
   my $attributes = shift;

   (defined $attributes) or ($attributes = '');

   $self->{entries}->{$ctlvar} = ''; # not used for buttons

   my $col = ++($self->{col});

   # only pack the button frame once all other controls have been created
   if (not defined $self->{b}) {
      $self->{b} = $self->{w}->Frame->pack; # frame for grid containing buttons
   }

   if (not defined $command) {
      my $callback = $self->{callback};
      if (defined $callback) {
         $command = sub{&$callback($ctlvar)};
      }
   }

   my $button = $self->{b}->Button(-text=>$ctllabel, -font=>'msgbox', -command=>$command);
   $button->grid(-row=>1, -column=>$col);
   $self->{controls}->{$ctlvar} = $button;

   if (defined $shortcutaltkey) {
      $self->{w}->bind("<Alt-KeyPress-$shortcutaltkey>", [$button => 'invoke']);
      my $underlinepos = index(lc($ctllabel),$shortcutaltkey);

      if ($underlinepos >= 0) {
         $button->configure(-underline=>$underlinepos);
      }
   }

   $self->{attr}->{$ctlvar} = "button $attributes ";
   $button->bind('<ButtonPress-1>', [$button => 'focus']);
   return $button;
}


1;
