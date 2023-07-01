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

   my $buttons = ['Generate', 'AutoWeight', 'Play', 'Flash', 'Start', 'Finish', 'Done', 'Cancel'];
   my $extype = $mdlg->{e}->{exercisetype};

####### up to here: make following into object properties as well as locals
   $self->{w} = $mdlg->{w}->DialogBox(-title=>"Morse Practice - $extype", -buttons=>$buttons); # exercise window

#   $self->{w}->fontCreate('msgbox',-family=>'helvetica', -size=>-14);

   my $xwdf = $self->{xwdf} = DialogFields->init($self->{w},sub{$self->exwindowcallback(@_)},300);
   my $e = $self->{e} = $xwdf->entries; # gridframe control values

   my $chars = CharCodes::getChars();
   $xwdf->addEntryField('Characters to practise', 'keylist', 40, $chars, undef, sub{$self->exwindowcallback('setexweights')});
   $xwdf->addEntryField('Extra character weights', 'xweights', 40, '');
   $xwdf->addEntryField('Practice session time (mins)', 'practicetime', 40, 2);
   $xwdf->addEntryField('Character WPM', 'wpm', 40, 20, 'w');
   $xwdf->addEntryField('Effective WPM', 'effwpm', 40, 20);
   $xwdf->addEntryField('Note pitch', 'pitch', 40, 600);
   $xwdf->addEntryField('Tone volume attenuation (dB)', 'attenuation', 40, '10');
   $xwdf->addEntryField('Dash-dot pitch shift (semitones)', 'pitchshift', 40, '0');
   $xwdf->addEntryField('Playing rate factor', 'playratefactor', 40, '1.00');
   $xwdf->addEntryField('Dash weight', 'dashweight', 40, 3);
   $xwdf->addEntryField('Min word length', 'minwordlength', 40, 1);
   $xwdf->addEntryField('Max word length', 'maxwordlength', 40, 6);
   $xwdf->addEntryField('Extra word spaces', 'extrawordspaces', 40, 0);
   $xwdf->addEntryField('Word list size', 'wordlistsize', 40, 0, undef, undef, 'locked');
   $xwdf->addEntryField('Dictionary sample size', 'dictsize', 40, 9999);
   $xwdf->addEntryField('Dictionary sample offset', 'dictoffset', 40, 0);
   $xwdf->addEntryField('Repeat words', 'repeatcnt', 40, 0);
   $xwdf->addCheckbuttonField('Allow backspace', 'allowbackspace',  1);
   $xwdf->addCheckbuttonField2('Use relative frequencies', 'userelfreq',  0, undef, sub{$self->exwindowcallback('setexweights')});
   $xwdf->addCheckbuttonField('Sync after each word', 'syncafterword',  1);
   $xwdf->addCheckbuttonField2('Character reaction times', 'measurecharreactions',  1);
   $xwdf->addCheckbuttonField('Retry mistakes', 'retrymistakes',  1);
   $xwdf->addCheckbuttonField2('Use random sequences', 'userandom',  1);
   $xwdf->addCheckbuttonField('Use pseudo words', 'usepseudo',  0);
   $xwdf->addCheckbuttonField2('Use English dictionary words', 'useedict',  0);
   $xwdf->addCheckbuttonField('Use phonemes', 'usephonemes',  0);
   $xwdf->addCheckbuttonField2('Use hundred common words', 'usehdict',  0);
   $xwdf->addCheckbuttonField('Use standard callsigns', 'usescalls',  0);
   $xwdf->addCheckbuttonField2('Use specified words', 'usespecified',  0);
   $xwdf->addCheckbuttonField('Use complex callsigns', 'useicalls',  0);
   $xwdf->addCheckbuttonField2('Use QSO terms', 'useqdict',  0);
   $xwdf->addCheckbuttonField('European prefixes', 'europrefix',  1);
   $xwdf->addCheckbuttonField2('Use QSO phrases', 'useqphrases',  0);

   $self->{d} = $xwdf->addWideTextField(undef, 'exercisetext', 10, 75, '');
   $self->{d}->focus;

   # buttons use callback by default
#   $xwdf->addButtonField('Next', 'next',  'n');
#   $xwdf->addButtonField('Calibrate', 'calibrate',  'c');
#   $xwdf->addButtonField('AutoWeight', 'autoweight',  'u');
#   $xwdf->addButtonField('Generate', 'generate',  'g');
#   $xwdf->addButtonField('Play', 'play',  'p');
#   $xwdf->addButtonField('Flash', 'flash',  'h');
#   $xwdf->addButtonField('Start', 'start',  's');
#   $xwdf->addButtonField('Finish', 'finish',  'f');
#   $xwdf->addButtonField('Quit', 'quit',  'q', sub{$self->{w}->destroy});

   $xwdf->addHiddenField('Running', 'running', 0);
   $xwdf->addHiddenField('AutoExtraWeights', 'autoextraweights', '');

   $self->{ex} = Exercise->init($self); # this will move to ExerciseDialog
   $self->{ex}->validateSettings();
   $self->{ex}->setexweights();
   # import default or previously set values
   foreach my $i (keys(%{$e})) {
      if (defined $mdlg->{e}->{$i}) {
         $e->{$i} = $mdlg->{e}->{$i};
      }
   }

   # set up button callbacks
   foreach my $bname (qw/Generate AutoWeight Play Flash Start Finish/) {
      my $bcontrol = $self->{w}->Subwidget("B_$bname");
      die "No control for $bname\n" unless defined($bcontrol);
      $bcontrol->configure(-command => sub{$self->exwindowcallback(lc($bname))});
   }

#   my $startbutton = $self->{w}->Subwidget('B_Start');
#   $startbutton->configure(-command => sub{$self->startexercise()});
#   my $finishbutton = $self->{w}->Subwidget('B_Finish');
#   $finishbutton->configure(-command => sub{$self->finishexercise()});
   $self->setControlState('normal');

   my $button = $self->{w}->Show;

   if ($button eq 'Done') {
      # save local changes with main dialog state
      foreach my $i (keys(%{$e})) {
         $mdlg->{e}->{$i} = $e->{$i};
      }
   }

   return $self;
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

   $self->{w}->Subwidget('B_Start')->configure(-state=>$state);
   $self->{w}->Subwidget('B_Done')->configure(-state=>$state);
   $self->{w}->Subwidget('B_Cancel')->configure(-state=>$state);
   $self->{w}->Subwidget('B_AutoWeight')->configure(-state=>$state);
   $self->{w}->Subwidget('B_Generate')->configure(-state=>$state);
   $self->{w}->Subwidget('B_Play')->configure(-state=>$state);
   $self->{w}->Subwidget('B_Flash')->configure(-state=>$state);

   # enable Finish button only during an exercise
   if ($state eq 'disabled') {
       $self->{w}->Subwidget('B_Finish')->configure(-state=>'normal');
   } else {
       $self->{w}->Subwidget('B_Finish')->configure(-state=>'disabled');
   }
}

1;

