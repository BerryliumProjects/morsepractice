#! /usr/bin/perl
use Tk;
use Tk::After;
use Audio::Data;
use Audio::Play;
use Time::HiRes qw(time usleep);

use lib '.';
use charcodes;  # definitions of characters as dit-dah sequences

use warnings;

%charcodes = %{CharCodes::getCharCodes()};

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
my $tonefreq = 800; # base
my $literal = 0; # 1 = treat .- and space as elements not characters
my $text = 0; # 1 = treat newlines as interword spaces
my $ratecorrection = 1.0;
my $dashweight = 3.0;
my $extrawordspaces = 0;
my $attenuation = 10;
my $pitchshift = 0; # dots and dashes are same pitch
my $abortpending = 0;

my $bufferinglimit = 3; # seconds


# enable asynchronous abort of a long playing text
local $SIG{'TERM'} = sub {$abortpending = 1};

if (defined $ARGV[0] and $ARGV[0] > 1) {
   $wpm = $ARGV[0];
} else {
   print "Usage: perl morseplayer2.pl wpm [effectivewpm] [tonefrequency] [ratecorrection] [dashweight] [extrawordspaces] [attenuation] [pitchshift] [switches]\n";
   print "Switches: -t = text (newlines split words); -l = literal (.- are elements not characters)\n";
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

if (defined $ARGV[3] and $ARGV[3] > 0) {
   $ratecorrection = $ARGV[3];
}

if (defined $ARGV[4] and $ARGV[4] > 1) {
   $dashweight = $ARGV[4];
}

if (defined $ARGV[5] and $ARGV[5] > 0) {
   $extrawordspaces = $ARGV[5];
}

if (defined $ARGV[6] and $ARGV[6] >= 0) {
   $attenuation = $ARGV[6];
} 

if (defined $ARGV[7] and $ARGV[7] > 0) {
   $pitchshift = $ARGV[7]; # semitones above/below base
} 

if (defined $ARGV[8] and $ARGV[8] eq '-l') {
   $literal = 1; # intepret - . and blank as dah/dit/intercharacter spacing 
} 

if (defined $ARGV[8] and $ARGV[8] eq '-t') {
   $text = 1; # treat newlines as interword spaces
} 

# adjust inter-word space length

if ($extrawordspaces > 0 and $extrawordspaces < 50) {
    $charcodes{' '} .= ('  ' x $extrawordspaces);
}

my @keylist = keys(%charcodes);
my $keylistlen = scalar(@keylist);


$svr = Audio::Play->new(1);
$svr->rate(40000);
$bitrate = $svr->rate; # may be lower than requested
#$ratecorrection = 1; # 9600/8000; # for some reason audio plays slower than it should by this factor 
print "Sampling rate: $bitrate\n";

$pulse = 1.2/$wpm;

$risetime = 3.0 / $tonefreq;
$risetime = 0.0075 if $risetime < 0.0075;
$risetime = $pulse/4 if $risetime > $pulse/4;
$risecnt = $risetime * $bitrate;

# average 5 letters + 1 space per standard word
$extrachar = 60 / 6 * (1.0 / $effwpm - 1.0 / $wpm);
$extrachar = 0 unless $extrachar > 0;

my $amplitude = 0.5 * 0.1 ** ($attenuation/20);

printf "WPM=%i, Effective WPM=%i, pulse=%ims, risetime=%ims, amplitude=%5.3f\n", $wpm, $effwpm, $pulse*1000, $risetime*1000, $amplitude;

$freqshiftfactor = 2.0 ** ($pitchshift / 24);

$wholedot = CreateElement(1, $tonefreq * $freqshiftfactor);
$wholedash = CreateElement($dashweight, $tonefreq / $freqshiftfactor);

$charsilence = Audio::Data->new(rate=>$bitrate);
$charsilence->silence($pulse * 2 / $ratecorrection);

$extracharsilence = Audio::Data->new(rate=>$bitrate);
$extracharsilence->silence($extrachar / $ratecorrection);

# ensure at least 200ms of silence at end of playing sequence
$bufferclearsilence = Audio::Data->new(rate=>$bitrate);
$bufferclearsilenceduration = 0.2;
$bufferclearsilence->silence($bufferclearsilenceduration / $ratecorrection);

my $charsilenceduration = $charsilence->duration * $ratecorrection;
my $extracharsilenceduration = $extracharsilence->duration * $ratecorrection;

my $prevblkline;

open(READY, "> $mp2readyfile"); close(READY); # signal ready for first input
our $expectedplayendtime = 0.0;
my $actualtime;
my @charendtimereports = ();
our $pulses = 0;

open (SI, "<-");

while (<SI>) {
   last if /^#/;
   chomp;   

   s/ +/ /g;

   if ($text) { # put one space at end of line
      s/ $//;
      $_ .= ' ';
   }

   my $chars = $_;
   my $elmseq;

   $actualtime = time();

   if ($actualtime > $expectedplayendtime) {
#      print "Recalibrated expected play end time\n"; #diags
      $expectedplayendtime = $actualtime;
      clearbuffer(); # buffer is empty so pcm device needs waking up first
   }

   foreach my $ch (split(//, $chars)) {
      last if $abortpending;
      my $elmseq;

      if ($literal) {
         $elmseq = $ch;
      } else {
         $elmseq = $charcodes{lc($ch)};
      }

      if (!defined $elmseq) {
         $ch = '='; # substitute a default character
         $elmseq = $charcodes{lc($ch)};
      }

      foreach my $element (split(//, $elmseq)) {
         if ($element eq '.') {
	    playdot();
         } elsif ($element eq '-') {
	    playdash();
	 } else { # intercharacter space
	    playspace();
         }
      }   

      playextraspace();
      print "\n" if $verbose;
      
      if ($ch eq ' ') {
         $pulses -= ($extrawordspaces * 2); # extra time doesn't contribute to copied pulse count
      }

      push @charendtimereports, "$ch\t$expectedplayendtime\t$pulses\n";
      $pulses = 0;

      # don't let audio buffer get too far ahead
      while ($expectedplayendtime > time() + $bufferinglimit) {
         sleep 1;
      }
   }


   # end of input line
   unless ($text) {
      # record a notional end time of an interword space
      my $notionalplayendtime = $expectedplayendtime + $charsilenceduration * 2 + $extracharsilenceduration;
      push @charendtimereports, " \t$notionalplayendtime\t4\n";
      clearbuffer(); # allow to flush
   }

   unless ($literal and $chars=~/-|\./) { # literal mode only flushes after a blank line
      open(STATS, ">> $mp2statsfile");
      print STATS @charendtimereports;
      close(STATS);
      @charendtimereports = ();
      open(READY, "> $mp2readyfile"); close(READY); # signal ready for next input
   }

   last if $abortpending;
}

close(SI);
clearbuffer();
sleep 1; # before $svr destructor called
# $svr->flush();
exit 0;

sub CreateElement {
   my $beeppulses = shift;
   my $freq = shift;

   my $beep = Audio::Data->new(rate=>$bitrate);
   my $duration = $beeppulses * $pulse + $risetime; # time start/stop from "half amplitude" points
   $beep->tone($freq * $ratecorrection, $duration / $ratecorrection, $amplitude);

   @beepdata = $beep->data;
   $samples = scalar(@beepdata);

   for ($i = 0; $i < $risecnt; $i++) {
      $beepdata[$i] *= ($i / $risecnt);
      $beepdata[$samples-$i-1] *= ($i / $risecnt);
   }

   $beep->data(@beepdata);

   $silence = Audio::Data->new(rate=>$bitrate);
   $silenceduration = $pulse - $risetime;
   $silence->silence($silenceduration / $ratecorrection);

   my $wholeelement = $beep . $silence;

   return $wholeelement;
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

sub playdot {
   print '.' if $verbose;
   safeplay($svr, $wholedot);
   $expectedplayendtime += ($wholedot->duration * $ratecorrection);
   $pulses += 2;
}

sub playdash {
   print '-' if $verbose;
   safeplay($svr, $wholedash);
   $expectedplayendtime += ($wholedash->duration * $ratecorrection);
   $pulses += ($dashweight + 1);
}

sub playspace {
   print '_'  if $verbose;
   safeplay($svr, $charsilence);
   $expectedplayendtime += $charsilenceduration;
   $pulses += 2;
}

sub playextraspace {
   safeplay($svr, $extracharsilence);
   $expectedplayendtime += $extracharsilenceduration;
}

sub clearbuffer {
   print '|'  if $verbose;
   safeplay($svr, $bufferclearsilence);
   $expectedplayendtime += $bufferclearsilenceduration;
}

