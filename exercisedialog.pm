#! /usr/bin/perl 
package ExerciseDialog;

use strict;
use warnings;

use Tk;
use Tk::ROText;
use Tk::DialogBox;

use Data::Dumper;
our $e;
our $xwdf;
our $xw;

sub show {
   my $extype = shift;
   my $mdlg = shift;

   my $buttons = ['Start', 'Finish', 'Done', 'Cancel']; 

   $xw = $mdlg->{w}->DialogBox(-title=>"Morse Practice - $extype", -buttons=>$buttons); # exercise window
   $xwdf = DialogFields->init($xw);
   $e = $xwdf->entries;

   if ($extype eq 'Single characters') {
      $xwdf->addEntryField('Characters to practise', 'keylist', 40);
      $xwdf->addEntryField('Extra character weights', 'xweights', 40);
   } elsif ($extype eq 'Random sequences') {
      $xwdf->addEntryField('Characters to practise', 'keylist', 40);
      $xwdf->addEntryField('Extra character weights', 'xweights', 40);
   } elsif ($extype eq 'Pseudo words') {
   } elsif ($extype eq 'Callsigns') {
      $e->{usescalls} = 1;
      $xwdf->addCheckbuttonField('Use complex callsigns', 'useicalls');
      $xwdf->addCheckbuttonField('European prefixes', 'europrefix');
   } elsif ($extype eq 'Common words') {
   } elsif ($extype eq 'Dictionary words') {
      $xwdf->addEntryField('Word list size', 'wordlistsize', 40);
      $xwdf->addEntryField('Dictionary sample size', 'dictsize', 40);
      $xwdf->addEntryField('Dictionary sample offset', 'dictoffset', 40);
   } elsif ($extype eq 'QSO terms') {
   } elsif ($extype eq 'QSO phrases') {
   } elsif ($extype eq 'Numbers') {
   }

   $xwdf->addEntryField('Effective WPM', 'effwpm', 40, 20);
   $xwdf->addEntryField('Min word length', 'minwordlength', 40, 1);
   $xwdf->addEntryField('Max word length', 'maxwordlength', 40, 6);
   $xwdf->addEntryField('Extra word spaces', 'extrawordspaces', 40, 0);
   $xwdf->addEntryField('Word list size', 'wordlistsize', 40, 0, undef, undef, 'locked');
   $xwdf->addEntryField('Dictionary sample size', 'dictsize', 40, 9999);
   $xwdf->addEntryField('Dictionary sample offset', 'dictoffset', 40, 0);
   $xwdf->addEntryField('Repeat words', 'repeatcnt', 40, 0);
   $xwdf->addCheckbuttonField('Allow backspace', 'allowbackspace',  1);
   $xwdf->addCheckbuttonField2('Use relative frequencies', 'userelfreq',  0, undef, sub{&{$xwdf->{callback}}('setexweights')});
   $xwdf->addCheckbuttonField('Sync after each word', 'syncafterword',  1);
   $xwdf->addCheckbuttonField2('Character reaction times', 'measurecharreactions',  1);
   $xwdf->addCheckbuttonField('Retry mistakes', 'retrymistakes',  1);
   $xwdf->addCheckbuttonField2('Use random sequences', 'userandom',  1);
   $xwdf->addCheckbuttonField('Use pseudo words', 'usepseudo',  0);
   $xwdf->addCheckbuttonField2('Use English dictionary words', 'useedict',  0);
   $xwdf->addCheckbuttonField('Use phonemes', 'usephonemes',  0);
   $xwdf->addCheckbuttonField2('Use hundred common words', 'usehdict',  0);
   $xwdf->addCheckbuttonField2('Use specified words', 'usespecified',  0);
   $xwdf->addCheckbuttonField2('Use QSO terms', 'useqdict',  0);
   $xwdf->addCheckbuttonField2('Use QSO phrases', 'useqphrases',  0);
      
   # import default or previously set values
   foreach my $i (keys(%{$e})) {
      if (defined $mdlg->{e}->{$i}) {
         $e->{$i} = $mdlg->{e}->{$i};
      }
   }

   my $startbutton = $xw->Subwidget('B_Start');
   $startbutton->configure(-command => sub{startexercise()});
   my $finishbutton = $xw->Subwidget('B_Finish');
   $finishbutton->configure(-command => sub{finishexercise()});
   setControlState('normal');

   my $button = $xw->Show;

   if ($button eq 'Done') {
      # save local changes with main dialog state
      foreach my $i (keys(%{$e})) {
         $mdlg->{e}->{$i} = $e->{$i};
      }
   }

}

sub startexercise {
   print "Start button clicked\n";
   setControlState('disabled');
}

sub finishexercise {
   print "Finish button clicked\n";
   setControlState('normal');
   print "End of activity\n";
} 

sub setControlState {
   my $state = shift;

   foreach my $k (keys(%{$e})) {
      if (($xwdf->{attr}->{$k} =~ /entry|checkbutton/) and not($xwdf->{attr}->{$k} =~ /locked/)) {
         $xwdf->{controls}->{$k}->configure(-state=>$state);
      }
   }

   $xw->Subwidget('B_Start')->configure(-state=>$state);
   $xw->Subwidget('B_Done')->configure(-state=>$state);
   $xw->Subwidget('B_Cancel')->configure(-state=>$state);

   # enable Finish button only during an exercise
   if ($state eq 'disabled') {
       $xw->Subwidget('B_Finish')->configure(-state=>'normal');
   } else {
       $xw->Subwidget('B_Finish')->configure(-state=>'disabled');
   }
}

1;

