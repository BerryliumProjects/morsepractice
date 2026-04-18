#! /usr/bin/perl
use Tk;
use Tk::After;
use Audio::Data;
use Audio::Play;
use Time::HiRes qw(time usleep);

use lib '.';
use charcodes;  # definitions of characters as dit-dah sequences

use warnings;
use strict;
my %charcodes = %{CharCodes::getCharCodes()};

my $mp2readyfile = '/var/tmp/mp2ready.txt'; 
my $mp2statsfile = '/var/tmp/mp2stats.txt';
my $mp2pidfile = '/var/tmp/mp2pid.txt';

unlink($mp2readyfile);
unlink($mp2statsfile);
# identify process so it can be aborted if requested
open(PIDFILE, "> $mp2pidfile"); print PIDFILE $$; close(PIDFILE);

my $verbose = 0; # show ./-
my $wpm;
my $effwpm;
my $tonefreq = 440; # standard A pitch
my $text = 0; # 1 = treat newlines as interword spaces
my $ratecorrection = 1.0;
my $dashweight = 3.0;
my $extrawordspaces = 0;
my $attenuation = 10;
my $pitchshift = 0; # dots and dashes are same pitch
my $abortpending = 0;

my $bufferinglimit = 3; # seconds
my $amplitude;
my $risetime;
my $extrachar;
my $pulse;
my $elements = {};

# enable asynchronous abort of a long playing text
local $SIG{'TERM'} = sub {$abortpending = 1};

if (defined $ARGV[0] and $ARGV[0] > 1) {
   $wpm = $ARGV[0];
} else {
   print "Usage: perl morseplayer2.pl wpm [effectivewpm] [tonefrequency] [dashweight] [extrawordspaces] [attenuation] [pitchshift]\n";
   print "To change settings: enter # setting newvalue\n";
   print "To finish playing, enter #\n";
   exit 1;
}

if (defined $ARGV[1] and $ARGV[1] > 1) {
   $effwpm = $ARGV[1];
} else {
   $effwpm = $wpm;
}

if (defined $ARGV[2] and $ARGV[2] > 1) {
   $tonefreq = $ARGV[2];
}

if (defined $ARGV[3] and $ARGV[3] > 1) {
   $dashweight = $ARGV[3];
}

if (defined $ARGV[4] and $ARGV[4] > 0) {
   $extrawordspaces = $ARGV[4];
}

if (defined $ARGV[5] and $ARGV[5] >= 0) {
   $attenuation = $ARGV[5];
} 

if (defined $ARGV[6] and $ARGV[6] > 0) {
   $pitchshift = $ARGV[6]; # semitones above/below base
} 

# adjust inter-word space length

if ($extrawordspaces > 0 and $extrawordspaces < 50) {
    $charcodes{' '} .= ('  ' x $extrawordspaces);
}

my @keylist = keys(%charcodes);
my $keylistlen = scalar(@keylist);


my $svr = Audio::Play->new(1);
# $svr->rate(40000); # uncomment if default bit rate is too low - will emit "audio_flush with state open" warning
my $bitrate = $svr->rate; # may be lower than requested
# print "Sampling rate: $bitrate\n";

generateAudioData();

open(READY, "> $mp2readyfile"); close(READY); # signal ready for first input
my $expectedplayendtime = 0.0;
my $actualtime;
my @charendtimereports = ();
my $pulses;

open (SI, "<-");

while (<SI>) {
   chomp;

   if (/^#/) {
      s/^[# ]+//; # trim start of line
      my ($setting, $newvalue) = split / /, $_;
      last unless $setting;

      # process settings changes
      if ($setting eq 'text') {
         $text = $newvalue;
      } elsif ($setting eq 'wpm') {
         $wpm = $newvalue;
         generateAudioData();
      } elsif ($setting eq 'effwpm') {
         $effwpm = $newvalue;
         generateAudioData();
      } elsif ($setting eq 'attenuation') {
         $attenuation = $newvalue;
         generateAudioData();
      } elsif ($setting eq 'ratecorrection') {
         $ratecorrection = $newvalue;
         generateAudioData();
      } elsif ($setting eq 'verbose') {
         $verbose = $newvalue;
      }

      next;
   }

   s/ +/ /g;

   if ($text) { # separate lines of continuous text by a space
      s/ $//;
      $_ .= ' ';
   }

   my $chars = $_;
   my $elmseq;

   $actualtime = time();

   if ($actualtime > $expectedplayendtime) {
      # Recalibrate expected play end time after unknown pause
      $expectedplayendtime = $actualtime;
   }

   foreach my $ch (split(//, $chars)) {
      last if $abortpending;
      my $pulses = 0;
      my $elmseq = $charcodes{lc($ch)};

      if (!defined $elmseq) {
         $ch = '='; # substitute a default character
         $elmseq = $charcodes{lc($ch)};
      }

      foreach my $element (split(//, $elmseq)) {
         playelement($element);

         if ($element eq '-') {
	         $pulses += $dashweight + 1;
         } else {
            $pulses += 2;
         }
      }

      playelement('_'); # extra inter-character spacing
      
      if ($ch eq ' ') {
         print "\n" if $verbose;
         $pulses -= ($extrawordspaces * 2); # extra time doesn't contribute to copied pulse count
      }

      push @charendtimereports, "$ch\t$expectedplayendtime\t$pulses\n";

      # don't let audio buffer get too far ahead
      while ($expectedplayendtime > time() + $bufferinglimit) {
         sleep 1;
      }
   }

   # end of input line
   unless ($text) {
      # record a notional end time of an interword space
      my $notionalplayendtime = $expectedplayendtime + $pulse * 4 + $extrachar;
      push @charendtimereports, " \t$notionalplayendtime\t4\n";
      playelement('|'); # flush buffer
   }

   open(STATS, ">> $mp2statsfile");
   print STATS @charendtimereports;
   close(STATS);
   @charendtimereports = ();
   open(READY, "> $mp2readyfile"); close(READY); # signal ready for next input

   last if $abortpending;
}

close(SI);
sleep 1; # before $svr destructor called
exit 0;

sub CreateElement {
   my $beeppulses = shift;
   my $freq = shift;
   my $beep = Audio::Data->new(rate=>$bitrate);

   my $risetime = 3.0 / $tonefreq;
   $risetime = 0.0075 if $risetime < 0.0075;
   $risetime = $pulse/4 if $risetime > $pulse/4;

   my $duration = $beeppulses * $pulse + $risetime; # time start/stop from "half amplitude" points
   $beep->tone($freq * $ratecorrection, $duration / $ratecorrection, $amplitude);

   my @beepdata = $beep->data;
   my $samples = scalar(@beepdata);
   my $risecnt = $risetime * $bitrate;

   for (my $i = 0; $i < $risecnt; $i++) {
      $beepdata[$i] *= ($i / $risecnt);
      $beepdata[$samples-$i-1] *= ($i / $risecnt);
   }

   $beep->data(@beepdata);

   my $silence = Audio::Data->new(rate=>$bitrate);
   my $silenceduration = $pulse - $risetime;
   $silence->silence($silenceduration / $ratecorrection);

   my $wholeelement = $beep . $silence;

   return $wholeelement;
}

sub CreateSilence {
   my $silenceduration = shift;

   my $silence = Audio::Data->new(rate=>$bitrate);
   $silence->silence($silenceduration / $ratecorrection);
   return $silence;
}

sub safeplay {
   my $svr= shift; # server
   my $au = shift; # audio

   my $brokenpipe = undef;

   local $SIG{__WARN__} = sub {
      my $msg = shift;
      $brokenpipe = ($msg =~ /Broken pipe/);
      print "Warning: $msg\n" unless $brokenpipe; # unexpected warning, show this 
   };

      $svr->play($au);
      print '!' if ($verbose and $brokenpipe);
      $brokenpipe = undef;
}

sub playelement {
   my $element = shift;
   print $element if $verbose;
   safeplay($svr, $elements->{$element});
   my $duration = $elements->{$element}->duration * $ratecorrection;
   $expectedplayendtime += $duration;
}

sub generateAudioData {
   $pulse = 1.2/$wpm;

   # average 5 letters + 1 space per standard word
   $extrachar = 60 / 6 * (1.0 / $effwpm - 1.0 / $wpm);
   $extrachar = 0 unless $extrachar > 0;
   my $freqshiftfactor = 2.0 ** ($pitchshift / 24);
   $amplitude = 0.5 * 0.1 ** ($attenuation/20);

   if ($verbose) {
      printf "WPM=%i, Effective WPM=%i, pulse=%ims, freq shift factor=%5.3f, amplitude=%5.3f\n", $wpm, $effwpm, $pulse*1000, $freqshiftfactor, $amplitude;
   }

   $elements->{'.'} = CreateElement(1, $tonefreq * $freqshiftfactor);
   $elements->{'-'} = CreateElement($dashweight, $tonefreq / $freqshiftfactor);
   $elements->{' '} = CreateSilence($pulse * 2);
   $elements->{'_'} = CreateSilence($extrachar);
   $elements->{'|'} = CreateSilence(0.2); # 200ms to clear buffer
}

