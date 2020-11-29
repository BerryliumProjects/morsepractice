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

   my $mwdf = $self->{mwdf} = DialogFields->init($self->{w},$callback,300);
   $self->{e} = $mwdf->entries; # gridframe control values

   $mwdf->addEntryField('Characters to practice', 'keylist', 40, '', undef, sub{&{$mwdf->{callback}}('setexweights')});
   $mwdf->addEntryField('Practice session time (mins)', 'practicetime', 40, 2);
   $mwdf->addEntryField('Min word length', 'minwordlength', 40, 1);
   $mwdf->addEntryField('Max word length', 'maxwordlength', 40, 9);
   $mwdf->addEntryField('Repeat words', 'repeatcnt', 40, 0);
   $mwdf->addEntryField('Character WPM', 'wpm', 40, 20, 'w');
   $mwdf->addEntryField('Effective WPM', 'effwpm', 40, 20);
   $mwdf->addEntryField('Note pitch', 'pitch', 40, 600);
   $mwdf->addEntryField('Playing rate factor', 'playratefactor', 40, '1.00');
   $mwdf->addEntryField('Dash weight', 'dashweight', 40, 3);
   $mwdf->addEntryField('Extra word spaces', 'extrawordspaces', 40, 0);
   $mwdf->addEntryField('Word list size', 'wordlistsize', 40, 0, undef, undef, 'locked');
   $mwdf->addEntryField('Dictionary sample size', 'dictsize', 40, 9999);
   $mwdf->addEntryField('Dictionary sample offset', 'dictoffset', 40, 0);
   $mwdf->addEntryField('Extra character weights', 'xweights', 40, '');
   $mwdf->addEntryField('Tone volume attenuation (dB)', 'attenuation', 40, '10');
   $mwdf->addEntryField('Dash-dot pitch shift (semitones)', 'pitchshift', 40, '0');
   $mwdf->addCheckbuttonField('Allow backspace', 'allowbackspace',  1);
   $mwdf->addCheckbuttonField2('Use relative frequencies', 'userelfreq',  1, undef, sub{&{$mwdf->{callback}}('setexweights')});
   $mwdf->addCheckbuttonField('Sync after each word', 'syncafterword',  1);
   $mwdf->addCheckbuttonField2('Character reaction times', 'measurecharreactions',  1);
   $mwdf->addCheckbuttonField('Retry mistakes', 'retrymistakes',  0);
   $mwdf->addCheckbuttonField2('Use random sequences', 'userandom',  1);
   $mwdf->addCheckbuttonField('Use pseudo words', 'usepseudo',  0);
   $mwdf->addCheckbuttonField2('Use English words', 'useedict',  0);
   $mwdf->addCheckbuttonField('Use phonemes', 'usephonemes',  0);
   $mwdf->addCheckbuttonField2('Use hundred common words', 'usehdict',  0);
   $mwdf->addCheckbuttonField('Use standard callsigns', 'usescalls',  0);
   $mwdf->addCheckbuttonField2('Use QSO terms', 'useqdict',  0);
   $mwdf->addCheckbuttonField('Use complex callsigns', 'useicalls',  0);
   $mwdf->addCheckbuttonField2('Use QSO phrases', 'useqphrases',  0);
   $mwdf->addCheckbuttonField('European prefixes', 'europrefix',  1);

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

