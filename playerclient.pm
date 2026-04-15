#! /usr/bin/perl 
use strict;
use warnings;
package PlayerClient;

use Data::Dumper;
use IO::Handle;
use Time::HiRes qw(time usleep);

use lib '.';

# constants
my $mp2readyfile = '/var/tmp/mp2ready.txt';
my $mp2pidfile = '/var/tmp/mp2pid.txt';
my $mp2statsfile = '/var/tmp/mp2stats.txt';
my $morseplayer = "./morseplayer2.pl";

sub init {
   my $class = shift;

   my $self = {};
   bless($self, $class);
   $self->{MP} = undef;
   unlink($mp2pidfile) if -f $mp2pidfile;
   return $self;
}

sub openStats {
   my $STATS;
   open($STATS, $mp2statsfile);
   return $STATS; 
}

sub closeStats {
   my $STATS = shift;
   close($STATS);
   unlink $mp2statsfile;
}

sub openPlayer {
   my $self = shift;
   my $e = shift; # ref to user parameters including audio settings
   my $textmode = shift; # optional boolean


   die "Opening Player when already connected"  if defined($self->{MP});

   if (!(defined $e)) {
      $self->openStandardPlayer; # fallback if no explicit parameters supplied
      return;
   }

   my @audiofields = qw/wpm effwpm pitch dashweight extrawordspaces attenuation pitchshift/;
   my %ehash = %{$e}; # simplifies taking a slice of the values
   my $openargs = join(' ', @ehash{@audiofields});
   open($self->{MP}, "|  perl $morseplayer $openargs") or die "Failed to connect to player";
   defined($self->{MP}) or die "Player pipe filehandle not defined";
   autoflush {$self->{MP}} 1;

   if ($textmode) {
      print {$self->{MP}} "# text 1\n";
   }

   if (defined($e->{playratefactor})) {
      my $playratefactor = $e->{playratefactor};

      if ($playratefactor != 1) {
         print {$self->{MP}} "# ratecorrection $playratefactor\n";
      }
   }

   unlink($mp2statsfile) if -f $mp2statsfile;
}

sub openStandardPlayer {
   my $self = shift;

   die "Opening Player when already connected"  if defined($self->{MP});

   open($self->{MP}, "|  perl $morseplayer 20") or die "Failed to connect to player";

   defined($self->{MP}) or die "Player pipe filehandle not defined";
   autoflush {$self->{MP}} 1;
   unlink($mp2statsfile) if -f $mp2statsfile;
}

sub closePlayer {
   my $self = shift;
   my $force = shift;

   return unless defined($self->{MP});

   if ($force) {
      open(PIDFILE, $mp2pidfile);
      my $mp2pid = <PIDFILE>;
      close(PIDFILE);

      chomp($mp2pid);

      kill('SIGTERM', $mp2pid); # ask player to terminate early
      unlink($mp2pidfile);
   } else {
      print {$self->{MP}} "#\n";
   }

   close($self->{MP});
   $self->{MP} = undef;
   $self->syncflush;
}

sub writePlayer {
   my $self = shift;
   my $text = shift;

   die unless defined($self->{MP});

   print {$self->{MP}} "$text\n";
}

sub playText {
   my $class = shift;
   my $e = shift; # user parameters
   my $ptext = shift;

   my $self = $class->init;

   $self->openPlayer($e, 1); # multi-line text mode
   $self->writePlayer("=  $ptext");
   $self->closePlayer;
}

sub calibrate {
   my $class = shift;
   my $e = shift; # user parameters
   my $self = $class->init;
   $self->openPlayer($e);

   # play a standard message at the selected pitch and wpm
   $self->writePlayer("paris paris");
   $self->closePlayer;
}

sub syncflush {
   my $self = shift;

   # Check that previous playing has finished so timings are accurate
   my $pollctr;

   for ($pollctr = 0; $pollctr < 50; $pollctr++) {
      last if (-f $mp2readyfile);
      usleep(20000); # microseconds
   }

   unlink($mp2readyfile) if -f $mp2readyfile;
}

1;

