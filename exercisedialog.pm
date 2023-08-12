#! /usr/bin/perl 
package ExerciseDialog;

use strict;
use warnings;

use Tk;
use Tk::ROText;
use Tk::DialogBox;

use Data::Dumper;
use Tk::After;

use lib '.';
use dialogfields;
use exercise;
use charcodes;

sub show {
   my $class = shift;
   my $self = {};
   bless($self, $class);
   my $mdlg = shift;

   my $extype = $mdlg->{e}->{exercisetype};

   my $buttons = ['Generate', 'Play', 'Flash', 'Start', 'Finish', 'Cancel'];

   if ($extype =~ /Single|Random|Numbers/) {
      splice(@$buttons, 1, 0, 'AutoWeight'); # only include this button if character weights are used
   }
  
   $self->{w} = $mdlg->{w}->DialogBox(-title=>"Morse Practice - $extype", -buttons=>$buttons); # exercise window

   my $xwdf = $self->{xwdf} = DialogFields->init($self->{w},sub{$self->exwindowcallback(@_)},300);
   my $e = $self->{e} = $xwdf->entries; # gridframe control values

   my $chars = CharCodes::getChars();

   if ($extype eq 'Numbers') {
      $chars = '0123456789.r';
   }
   
   $xwdf->addEntryField('Practice session time (mins)', 'practicetime', 40, 2);

   if ($extype =~ /Single|Random|Numbers/) {
      $xwdf->addEntryField('Characters to practise', 'keylist', 40, $chars, undef, sub{$self->exwindowcallback('setexweights')});
      $xwdf->addEntryField('Extra character weights', 'xweights', 40, '');
   } else {
      $xwdf->addHiddenField('Characters to practise', 'keylist', '' );
      $xwdf->addHiddenField('Extra character weights', 'xweights', '');
   }

   if ($extype =~ /Random|Phoneme|Pseudo|Common|Dictionary|Numbers|QSO terms/) {
      $xwdf->addEntryField('Min word length', 'minwordlength', 40, 1);
      $xwdf->addEntryField('Max word length', 'maxwordlength', 40, 6);
   } elsif ($extype =~ 'Single') {
      $xwdf->addHiddenField('Min word length', 'minwordlength', 1);
      $xwdf->addHiddenField('Max word length', 'maxwordlength', 1);
   } else { # ignored but max word length must be > 1
      $xwdf->addHiddenField('Min word length', 'minwordlength', 9);
      $xwdf->addHiddenField('Max word length', 'maxwordlength', 9);
   }

   if ($extype eq 'Dictionary words') {
      $xwdf->addEntryField('Word list size', 'wordlistsize', 40, 0, undef, undef, 'locked');
      $xwdf->addEntryField('Dictionary sample size', 'dictsize', 40, 9999);
      $xwdf->addEntryField('Dictionary sample offset', 'dictoffset', 40, 0);
   } else {
      $xwdf->addHiddenField('Word list size', 'wordlistsize', 0);
      $xwdf->addHiddenField('Dictionary sample size', 'dictsize', 0);
      $xwdf->addHiddenField('Dictionary sample offset', 'dictoffset', 0);
   }

   $xwdf->addEntryField('Repeat words', 'repeatcnt', 40, 0);
   
   if ($extype =~ /Single|Random/) {
      $xwdf->addCheckbuttonField('Use relative frequencies', 'userelfreq',  0, undef, sub{$self->exwindowcallback('setexweights')});
   } else {
      $xwdf->addHiddenField('Use relative frequencies', 'userelfreq',  0);
   }

   if ($extype ne 'Single characters') {
      $xwdf->addCheckbuttonField('Sync after each word', 'syncafterword',  1);
      $xwdf->addCheckbuttonField('Allow backspace', 'allowbackspace',  1);
   } else { 
      $xwdf->addHiddenField('Sync after each word', 'syncafterword',  1);
      $xwdf->addHiddenField('Allow backspace', 'allowbackspace',  0);
   }

   $xwdf->addCheckbuttonField('Character reaction times', 'measurecharreactions',  1);
   $xwdf->addCheckbuttonField('Retry mistakes', 'retrymistakes',  1);
   $xwdf->addHiddenField('Use random sequences', 'userandom',  0);
   $xwdf->addHiddenField('Use pseudo words', 'usepseudo',  0);
   $xwdf->addHiddenField('Use English dictionary words', 'useedict',  0);
   $xwdf->addHiddenField('Use phonemes', 'usephonemes',  0);
   $xwdf->addHiddenField('Use hundred common words', 'usehdict',  0);

   if ($extype =~ /words|terms|Phoneme/) {
      $xwdf->addCheckbuttonField('Use specified words', 'usespecified',  0);
   } else {
      $xwdf->addHiddenField('Use specified words', 'usespecified',  0);
   }

   if ($extype eq 'Callsigns') {
      $xwdf->addCheckbuttonField('Use standard callsigns', 'usescalls',  1);
      $xwdf->addCheckbuttonField('European prefixes', 'europrefix',  1);
      $xwdf->addCheckbuttonField('Use complex callsigns', 'useicalls',  0);
   } else {
      $xwdf->addHiddenField('Use standard callsigns', 'usescalls',  0);
      $xwdf->addHiddenField('Use complex callsigns', 'useicalls',  0);
      $xwdf->addHiddenField('European prefixes', 'europrefix',  1);
   }
   
   $xwdf->addHiddenField('Use QSO terms', 'useqdict',  0);
   $xwdf->addHiddenField('Use QSO phrases', 'useqphrases',  0);

   $self->{d} = $xwdf->addWideTextField(undef, 'exercisetext', 10, 75, '');
   $self->{d}->focus;

   $xwdf->addHiddenField('Running', 'running', 0);
   $xwdf->addHiddenField('AutoExtraWeights', 'autoextraweights', '');


   # create hidden fields matching those on main dialog
   $xwdf->addHiddenField('Character WPM', 'wpm');
   $xwdf->addHiddenField('Effective WPM', 'effwpm');
   $xwdf->addHiddenField('Note pitch', 'pitch');
   $xwdf->addHiddenField('Tone volume attenuation (dB)', 'attenuation');
   $xwdf->addHiddenField('Dash-dot pitch shift (semitones)', 'pitchshift');
   $xwdf->addHiddenField('Playing rate factor', 'playratefactor');
   $xwdf->addHiddenField('Dash weight', 'dashweight');
   $xwdf->addHiddenField('Extra word spaces', 'extrawordspaces');

   # import default or previously set values
   foreach my $i (keys(%{$e})) {
      if (defined $mdlg->{e}->{$i}) {
         $e->{$i} = $mdlg->{e}->{$i};
      }
   }

   if ($extype eq 'Single characters') {
      $e->{userandom} = 1;
   } elsif ($extype eq  'Random sequences') {
      $e->{userandom} = 1;
   } elsif ($extype eq  'Phonemes') {
      $e->{usephonemes} = 1;
   } elsif ($extype eq  'Pseudo words') {
      $e->{usepseudo} = 1;
   } elsif ($extype eq  'Common words') {
      $e->{usehdict} = 1;
   } elsif ($extype eq  'Dictionary words') {
      $e->{useedict} = 1;
   } elsif ($extype eq  'QSO terms') {
      $e->{useqdict} = 1;
   } elsif ($extype eq  'QSO phrases') {
      $e->{useqphrases} = 1;
   } elsif ($extype eq  'Numbers') {
      $e->{userandom} = 1;
   }

   $self->{ex} = Exercise->init($self);
   $self->{ex}->validateSettings();
   $self->{ex}->setexweights();

   # set up button callbacks
   foreach my $bname (qw/Generate AutoWeight Play Flash Start Finish/) {
      my $bcontrol = $self->{w}->Subwidget("B_$bname");
      if (defined($bcontrol)) {
         $bcontrol->configure(-command => sub{$self->exwindowcallback(lc($bname))});
      }
   }

#   my $startbutton = $self->{w}->Subwidget('B_Start');
#   $startbutton->configure(-command => sub{$self->startexercise()});
#   my $finishbutton = $self->{w}->Subwidget('B_Finish');
#   $finishbutton->configure(-command => sub{$self->finishexercise()});
   $self->setControlState('normal');

   my $button = $self->{w}->Show;

#   if ($button eq 'Done') {
#      # save local changes with main dialog state
#      foreach my $i (keys(%{$e})) {
#         $mdlg->{e}->{$i} = $e->{$i};
#      }
#   }

#   return $self;
}


sub startusertextinput {
   my $self = shift;

   $self->{d}->bind('<KeyPress>', [\&exercisekeyentered, Ev('A'), $self]); # automatically supplies a reference to $d as first argument
}

sub stopusertextinput {
   my $self = shift;

   $self->{d}->bind('<KeyPress>', undef);
}

sub exercisekeyentered {
   my $obj = shift; # automatically supplied reference to callback sender
   my $ch = shift;
   my $self = shift;
   $self->exwindowcallback('exercisekey', $ch);
}


sub exwindowcallback {
   my $self = shift;
   my $id = shift; # name of control firing event
   my $ex = $self->{ex};

   if ($id eq 'exercisekey') {
      my $ch = shift;
      $ex->checkchar($ch);
   } elsif ($id eq 'next') {
      runexercise();
   } elsif ($id eq 'setexweights') {
      $ex->setexweights();
   } elsif ($id eq 'calibrate') {
#      my $ex = Exercise->init($self);
      $ex->calibrate;
   } elsif ($id eq 'autoweight') {
      $ex->autoweight();
   } elsif ($id eq 'generate') {
      $ex->validateSettings();
      $ex->prepareTest();
      my $d = $self->{xwdf}->control('exercisetext');
      $d->Contents($ex->generateText());
   } elsif ($id eq 'play') {
      $ex->validateSettings();
      $ex->prepareTest();
      $ex->playText();
   } elsif ($id eq 'flash') {
      $ex->validateSettings();
      $ex->prepareTest();
      $ex->flashText();
   } elsif ($id eq 'start') {
      $ex->validateSettings();
      $ex->prepareTest();
      $ex->startAuto();
   } elsif ($id eq 'finish') {
      $ex->abortAuto();
   }
}

sub startexercise {
   my $self = shift;
   print "Start button clicked\n";
   $self->setControlState('disabled');
}

sub finishexercise {
   my $self = shift;
   print "Finish button clicked\n";
   $self->setControlState('normal');
   print "End of activity\n";
}

sub setControlState {
   my $self = shift;
   my $state = shift;
   my $xwdf = $self->{xwdf};
   my $e = $self->{e};

   foreach my $k (keys(%{$e})) {
      if (($xwdf->{attr}->{$k} =~ /entry|checkbutton/) and not($xwdf->{attr}->{$k} =~ /locked/)) {
         $xwdf->{controls}->{$k}->configure(-state=>$state);
      }
   }

   foreach my $bname (qw/Generate AutoWeight Play Flash Start Cancel/) {
      my $bcontrol = $self->{w}->Subwidget("B_$bname");
      if (defined($bcontrol)) {
         $bcontrol->configure(-state => $state);
      }
   }

   # enable Finish button only during an exercise
   if ($state eq 'disabled') {
       $self->{w}->Subwidget('B_Finish')->configure(-state=>'normal');
   } else {
       $self->{w}->Subwidget('B_Finish')->configure(-state=>'disabled');
   }
}

1;

