#! /usr/bin/perl 
package MainDialog;

use strict;
use warnings;

use Tk;
use Tk::ROText;
use Tk::DialogBox;

use Data::Dumper;
use Tk::After;

use lib '.';
use dialogfields;
use exercisedialog;
use exercise;
use playerclient;

sub init {
   my $class = shift;
   my $self = {};
   bless($self, $class);

   $self->{w} = MainWindow->new();

   $self->{w}->fontCreate('msgbox',-family=>'helvetica', -size=>-14);

   my $mwdf = $self->{mwdf} = DialogFields->init($self->{w},sub{mainwindowcallback($self, @_)},300);
   $self->{e} = $mwdf->entries; # gridframe control values

   my $lb = $mwdf->addListboxField('Exercise type', 'exercisetype', 40, '');
   $lb->insert('end', 'Single characters');
   $lb->insert('end', 'Random sequences');
   $lb->insert('end', 'Phonemes');
   $lb->insert('end', 'Pseudo words');
   $lb->insert('end', 'Numbers');
   $lb->insert('end', 'Callsigns');
   $lb->insert('end', 'Common words');
   $lb->insert('end', 'Dictionary words');
   $lb->insert('end', 'QSO terms');
   $lb->insert('end', 'QSO phrases');
   $lb->selectionSet(0);
   $self->{e}->{exercisetype} = 'Single characters';

   $mwdf->addEntryField('Character WPM', 'wpm', 40, 20, 'w');
   $mwdf->addEntryField('Effective WPM', 'effwpm', 40, 20);
   $mwdf->addEntryField('Note pitch', 'pitch', 40, 600);
   $mwdf->addEntryField('Tone volume attenuation (dB)', 'attenuation', 40, '10');
   $mwdf->addEntryField('Dash-dot pitch shift (semitones)', 'pitchshift', 40, '0');
   $mwdf->addEntryField('Playing rate factor', 'playratefactor', 40, '1.00');
   $mwdf->addEntryField('Dash weight', 'dashweight', 40, 3);
   $mwdf->addEntryField('Extra word spaces', 'extrawordspaces', 40, 0);

   # buttons use callback by default
   $mwdf->addButtonField('Calibrate', 'calibrate',  'c');
   $mwdf->addButtonField('Next', 'next',  'n');
   $mwdf->addButtonField('Quit', 'quit',  'q', sub{$self->{w}->destroy});

   $mwdf->addHiddenField('', 'prev_extype', '');
   return $self;
}

sub show {
   my $self = shift; 
   $self->{w}->MainLoop();
}


sub setControlState {
   my $self = shift;
   my $state = shift;

   my $mwdf = $self->{mwdf};

   foreach my $k (keys(%{$self->{e}})) {
if (!defined($mwdf->{attr}->{$k})) {print "Attributes undefined for '$k'\n"};
      if (($mwdf->{attr}->{$k} =~ /entry|checkbutton/) and not($mwdf->{attr}->{$k} =~ /locked/)) {
         $mwdf->{controls}->{$k}->configure(-state=>$state);
      }
   }

   $mwdf->{controls}->{calibrate}->configure(-state=>$state);
}

sub mainwindowcallback {
   my $self = shift;
   my $id = shift; # name of control firing event

   if ($id eq 'next') {
      ExerciseDialog->show($self);
   } elsif ($id eq 'calibrate') {
      $self->validateAudioSettings();
      PlayerClient->calibrate($self->{e});
   }
}

sub validateAudioSettings {
   my $self = shift;
   my $e = $self->{e};

   if ($e->{pitchshift} eq '') {
      $e->{pitchshift} = 0;
   }
}

1;

