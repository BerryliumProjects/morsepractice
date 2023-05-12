#! /usr/bin/perl 
package OptionsDialog;

use strict;
use warnings;

use Tk;
use Tk::ROText;
use Tk::DialogBox;

use Data::Dumper;

sub show {
   my $extype = shift;
   my $mdlg = shift;

   my $ow = $mdlg->{w}->DialogBox(-title=>'Exercise Options', -buttons=>['OK', 'Cancel']); # results window
   my $owdf = DialogFields->init($ow);
   my $e = $owdf->entries;

   if ($extype eq 'Single characters') {
      $owdf->addEntryField('Characters to practise', 'keylist', 40);
      $owdf->addEntryField('Extra character weights', 'xweights', 40);
   } elsif ($extype eq 'Random sequences') {
      $owdf->addEntryField('Characters to practise', 'keylist', 40);
      $owdf->addEntryField('Extra character weights', 'xweights', 40);
   } elsif ($extype eq 'Pseudo words') {
   } elsif ($extype eq 'Callsigns') {
      $e->{usescalls} = 1;
      $owdf->addCheckbuttonField('Use complex callsigns', 'useicalls');
      $owdf->addCheckbuttonField('European prefixes', 'europrefix');
   } elsif ($extype eq 'Common words') {
   } elsif ($extype eq 'Dictionary words') {
      $owdf->addEntryField('Word list size', 'wordlistsize', 40);
      $owdf->addEntryField('Dictionary sample size', 'dictsize', 40);
      $owdf->addEntryField('Dictionary sample offset', 'dictoffset', 40);
   } elsif ($extype eq 'QSO terms') {
   } elsif ($extype eq 'QSO phrases') {
   } elsif ($extype eq 'Numbers') {
   }

   $owdf->addEntryField('Effective WPM', 'effwpm', 40, 20);
   $owdf->addEntryField('Min word length', 'minwordlength', 40, 1);
   $owdf->addEntryField('Max word length', 'maxwordlength', 40, 6);
   $owdf->addEntryField('Extra word spaces', 'extrawordspaces', 40, 0);
   $owdf->addEntryField('Word list size', 'wordlistsize', 40, 0, undef, undef, 'locked');
   $owdf->addEntryField('Dictionary sample size', 'dictsize', 40, 9999);
   $owdf->addEntryField('Dictionary sample offset', 'dictoffset', 40, 0);
   $owdf->addEntryField('Repeat words', 'repeatcnt', 40, 0);
   $owdf->addCheckbuttonField('Allow backspace', 'allowbackspace',  1);
   $owdf->addCheckbuttonField2('Use relative frequencies', 'userelfreq',  0, undef, sub{&{$owdf->{callback}}('setexweights')});
   $owdf->addCheckbuttonField('Sync after each word', 'syncafterword',  1);
   $owdf->addCheckbuttonField2('Character reaction times', 'measurecharreactions',  1);
   $owdf->addCheckbuttonField('Retry mistakes', 'retrymistakes',  1);
   $owdf->addCheckbuttonField2('Use random sequences', 'userandom',  1);
   $owdf->addCheckbuttonField('Use pseudo words', 'usepseudo',  0);
   $owdf->addCheckbuttonField2('Use English dictionary words', 'useedict',  0);
   $owdf->addCheckbuttonField('Use phonemes', 'usephonemes',  0);
   $owdf->addCheckbuttonField2('Use hundred common words', 'usehdict',  0);
   $owdf->addCheckbuttonField2('Use specified words', 'usespecified',  0);
   $owdf->addCheckbuttonField2('Use QSO terms', 'useqdict',  0);
   $owdf->addCheckbuttonField2('Use QSO phrases', 'useqphrases',  0);
      
   # import default or previously set values
   foreach my $i (keys(%{$e})) {
      $e->{$i} = $mdlg->{e}->{$i};
   }

   my $button = $ow->Show;

   if ($button eq 'OK') {
      # apply local changes to main dialog settings
      foreach my $i (keys(%{$e})) {
         $mdlg->{e}->{$i} = $e->{$i};
      }
   }

}

1;

