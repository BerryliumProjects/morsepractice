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

   # initialise all possible exercise parameters - change type to visible if required
   my @stringexfields = qw/extype practicetime keylist xweights AutoExtraWeights/;
   my @numexfields = qw/kochlevel minwordlength maxwordlength wordlistsize dictsize dictoffset repeatcnt
      userelfreq syncafterword allowbackspace measurecharreactions retrymistakes usespecified usescalls useicalls europrefix sessionPB/;
   my @inheritedfields = qw/wpm effwpm pitch attenuation pitchshift playratefactor dashweight extrawordspaces/;

   foreach my $fname (@stringexfields, @inheritedfields) {
      $xwdf->addHiddenField('', $fname, '');
   }

   foreach my $fname (@numexfields) {
      $xwdf->addHiddenField('', $fname, 0);
   }

   $e->{extype} = $extype;

   my $chars = CharCodes->getChars();

   if ($extype eq 'Numbers') {
      $chars = '0123456789.r';
   }
   
   $xwdf->addEntryField('Practice session time (mins)', 'practicetime', 40, 2);

   if ($extype =~ /Single|Random|Numbers/) {
      $xwdf->addEntryField('Characters to practise', 'keylist', 40, $chars, undef, sub{$self->exwindowcallback('setexweights')});
      $xwdf->addEntryField('Extra character weights', 'xweights', 40, '');
   }

   if ($extype =~ /Single|Random/) {
      $xwdf->addEntryField('Koch method level', 'kochlevel', 40, 0, undef, sub{$self->exwindowcallback('setkochlevel')});
   }

   if ($extype =~ /Random|Phoneme|Pseudo|Common|Dictionary|Numbers|QSO terms/) {
      $xwdf->addEntryField('Min word length', 'minwordlength', 40, 1);
      $xwdf->addEntryField('Max word length', 'maxwordlength', 40, 6);
   } elsif ($extype =~ 'Single') {
      $e->{minwordlength} = 1;
      $e->{maxwordlength} = 1;
   } else { # ignored but max word length must be > 1
      $e->{minwordlength} = 9;
      $e->{maxwordlength} = 9;
   }

   if ($extype eq 'Dictionary words') {
      $xwdf->addEntryField('Word list size', 'wordlistsize', 40, 0, undef, undef, 'locked');
      $xwdf->addEntryField('Dictionary sample size', 'dictsize', 40, 9999);
      $xwdf->addEntryField('Dictionary sample offset', 'dictoffset', 40, 0);
   }

   $xwdf->addEntryField('Repeat words', 'repeatcnt', 40, 0);
   
   if ($extype =~ /Single|Random/) {
      $xwdf->addCheckbuttonField('Use relative frequencies', 'userelfreq',  0, undef, sub{$self->exwindowcallback('setexweights')});
   }

   if ($extype ne 'Single characters') {
      $xwdf->addCheckbuttonField('Sync after each word', 'syncafterword',  1);
      $xwdf->addCheckbuttonField('Allow backspace', 'allowbackspace',  1);
   } else { 
      $e->{syncafterword} = 1;
   }

   $xwdf->addCheckbuttonField('Character reaction times', 'measurecharreactions',  1);
   $xwdf->addCheckbuttonField('Retry mistakes', 'retrymistakes',  1);

   if ($extype =~ /words|terms|Phoneme/) {
      $xwdf->addCheckbuttonField('Use specified words', 'usespecified',  0);
   }

   if ($extype eq 'Callsigns') {
      $xwdf->addCheckbuttonField('Use standard callsigns', 'usescalls',  1);
      $xwdf->addCheckbuttonField('European prefixes', 'europrefix',  1);
      $xwdf->addCheckbuttonField('Use complex callsigns', 'useicalls',  0);
   } else {
      $e->{europrefix} = 1;
   }
   
   $self->{d} = $xwdf->addWideTextField(undef, 'exercisetext', 10, 75, '');
   $self->{d}->focus;

   $e->{running} = 0;

   # import default or previously set values
   foreach my $i (keys(%{$e})) {
      if (defined $mdlg->{e}->{$i}) {
         $e->{$i} = $mdlg->{e}->{$i};
      }
   }

   # retain previous settings for same exercise type after adjusting audio
   if ($extype eq $mdlg->{e}->{prev_extype}) {
      foreach my $i (keys(%{$e})) {
         my $prevkey = "prev_$i";

         if (defined $mdlg->{e}->{$prevkey}) {
             $e->{$i} = $mdlg->{e}->{$prevkey};
         }
      }
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

   $self->setControlState('normal');

   my $button = $self->{w}->Show;

   $mdlg->{e}->{prev_extype} = $extype;

   # save local settings with main dialog state
   foreach my $i (@stringexfields, @numexfields) {
      my $prevkey = "prev_$i";
      $mdlg->{e}->{$prevkey} = $e->{$i};
   }
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
   } elsif ($id eq 'setexweights') {
      $ex->setexweights();
   } elsif ($id eq 'setkochlevel') {
      $ex->setkochlevel();
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
      my $attr = $xwdf->{attr}->{k};

      if (defined $attr) {
         if (($attr =~ /entry|checkbutton/) and not($attr =~ /locked/)) {
            $xwdf->{controls}->{$k}->configure(-state=>$state);
         }
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

