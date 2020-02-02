#! /usr/bin/perl 
package MainDialog;

use strict;
use warnings;

use Tk;
use Tk::ROText;
use Tk::DialogBox;

use Data::Dumper;
use Tk::After;

use dialogfields;

sub init {
   my $class = shift;
   my $callback = shift;

   my $self = {};
   bless($self, $class);

   $self->{w} = MainWindow->new();

   $self->{w}->fontCreate('msgbox',-family=>'helvetica', -size=>-14);

   my $mwdf = $self->{mwdf} = DialogFields->init($self->{w},$callback);
   $self->{e} = $mwdf->entries; # gridframe control values

   $mwdf->addEntryField('Characters to practice', 'keylist', 40, '', undef, sub{&{$mwdf->{callback}}('setexweights')});
   $mwdf->addEntryField('Practice session time (mins)', 'practicetime', 40, 2);
   $mwdf->addEntryField('Min Word Length', 'minwordlength', 40, 1);
   $mwdf->addEntryField('Max Word Length', 'maxwordlength', 40, 9);
   $mwdf->addEntryField('Repeat words', 'repeatcnt', 40, 0);
   $mwdf->addEntryField('Character WPM', 'wpm', 40, 20, 'w');
   $mwdf->addEntryField('Effective WPM', 'effwpm', 40, 20);
   $mwdf->addEntryField('Note Pitch', 'pitch', 40, 600);
   $mwdf->addEntryField('Playing rate factor', 'playratefactor', 40, '1.00');
   $mwdf->addEntryField('Dash Weight', 'dashweight', 40, 3);
   $mwdf->addEntryField('Extra word spaces', 'extrawordspaces', 40, 0);

   $mwdf->addCheckbuttonField('Allow backspace', 'allowbackspace',  1);
   $mwdf->addCheckbuttonField('Use relative frequencies', 'userelfreq',  1, undef, sub{&{$mwdf->{callback}}('setexweights')});
   $mwdf->addCheckbuttonField('Sync after each word', 'syncafterword',  1);
   $mwdf->addCheckbuttonField('Retry mistakes', 'retrymistakes',  0);
   $mwdf->addCheckbuttonField('Use Random Sequences', 'userandom',  1);
   $mwdf->addCheckbuttonField('Use Pseudo Words', 'usepseudo',  0);
   $mwdf->addCheckbuttonField('Use English Dictionary', 'useedict',  0);
   $mwdf->addCheckbuttonField('Use QSO Dictionary', 'useqdict',  0);
   $mwdf->addCheckbuttonField('Use QSO Phrases', 'useqphrases',  0);
   $mwdf->addCheckbuttonField('Use Standard Callsigns', 'usescalls',  0);
   $mwdf->addCheckbuttonField('Use Complex Callsigns', 'useicalls',  0);
   $mwdf->addCheckbuttonField('Measure character reaction times', 'measurecharreactions',  1);

   $mwdf->addEntryField('Word list size', 'wordlistsize', 40, 0, undef, undef, 'locked');
   $mwdf->addEntryField('Dictionary Sample Size', 'dictsize', 40, 9999);
   $mwdf->addEntryField('Dictionary Sample Offset', 'dictoffset', 40, 0);
   $mwdf->addEntryField('Extra Character Weights', 'xweights', 40, '');


   $self->{d} = $mwdf->addWideTextField(undef, 'exercisetext', 10, 75, '');
   $self->{d}->focus;

   # buttons use callback by default
   $mwdf->addButtonField('Calibrate', 'calibrate',  'c');
   $mwdf->addButtonField('AutoWeight', 'autoweight',  'u');
   $mwdf->addButtonField('Generate', 'generate',  'g');
   $mwdf->addButtonField('Play', 'play',  'p');
   $mwdf->addButtonField('Flash', 'flash',  'h');
   $mwdf->addButtonField('Start', 'start',  's');
   $mwdf->addButtonField('Finish', 'finish',  'f');
   $mwdf->addButtonField('Quit', 'quit',  'q', sub{$self->{w}->destroy});

   return $self;
}

sub show {
   my $self = shift; 
   $self->{w}->MainLoop();
}

sub startusertextinput {
   my $self = shift;

   $self->{d}->bind('<KeyPress>', [\&exercisekeyentered, Ev('A'), $self->{mwdf}]); # automatically supplies a reference to $d as first argument
}

sub stopusertextinput {
   my $self = shift;

   $self->{d}->bind('<KeyPress>', undef);
}

sub exercisekeyentered {
   my $obj = shift; # automatically supplied reference to callback sender
   my $ch = shift;
   my $mwdf = shift;
   my $callback = $mwdf->{callback};
   &$callback('exercisekey', $ch);
}

sub setControlState {
   my $self = shift;
   my $state = shift;

   my $mwdf = $self->{mwdf};

   foreach my $k (keys(%{$self->{e}})) {
      if (($mwdf->{attr}->{$k} =~ /entry|checkbutton/) and not($mwdf->{attr}->{$k} =~ /locked/)) {
         $mwdf->{controls}->{$k}->configure(-state=>$state);
      }
   }

   $mwdf->{controls}->{calibrate}->configure(-state=>$state);
   $mwdf->{controls}->{autoweight}->configure(-state=>$state);
   $mwdf->{controls}->{generate}->configure(-state=>$state);
   $mwdf->{controls}->{play}->configure(-state=>$state);
   $mwdf->{controls}->{start}->configure(-state=>$state);

   # enable Finish button only during an exercise
   if ($state eq 'disabled') {
       $mwdf->{controls}->{finish}->configure(-state=>'normal');
   } else {
       $mwdf->{controls}->{finish}->configure(-state=>'disabled');
   }
}

1;

