#! /usr/bin/perl
use Tk;
use Tk::After;
use Audio::Data;
use Audio::Play;
use Time::HiRes qw(time usleep);

use charcodes;  # definitions of characters as dit-dah sequences

use warnings;

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
my $tonefreq = 800;
my $literal = 0; # 1 = treat .- and space as elements not characters
my $text = 0; # 1 = treat newlines as interword spaces
my $ratecorrection = 1.0;
my $dashweight = 3.0;
my $extrawordspaces = 0;
my $abortpending = 0;

my $bufferinglimit = 3; # seconds


# enable asynchronous abort of a long playing text
local $SIG{'TERM'} = sub {$abortpending = 1};

if (defined $ARGV[0] and $ARGV[0] > 1) {
   $wpm = $ARGV[0];
} else {
   print "Usage: perl morseplayer2.pl wpm [effectivewpm] [tonefrequency] [ratecorrection] [dashweight] [extrawordspaces] [switches]\n";
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

if (defined $ARGV[5] and $ARGV[5] > 1) {
   $extrawordspaces = $ARGV[5];
}

if (defined $ARGV[6] and $ARGV[6] eq '-l') {
   $literal = 1; # intepret - . and blank as dah/dit/intercharacter spacing 
} 

if (defined $ARGV[6] and $ARGV[6] eq '-t') {
   $text = 1; # intepret - . and blank as dah/dit/intercharacter spacing 
} 

# adjust inter-word space length

if ($extrawordspaces > 0 and $extrawordspaces < 50) {
    $charcodes{' '} .= (' ' x $extrawordspaces);
}

my @keylist = keys(%charcodes);
my $keylistlen = scalar(@keylist);


$svr = Audio::Play->new(1);
$bitrate = $svr->rate;
#$ratecorrection = 1; # 9600/8000; # for some reason audio plays slower than it should by this factor 
print "Sampling rate: $bitrate\n";

$pulsems = 1200/$wpm;

$risetime = 3 / $tonefreq;
$risetime = 0.02 if $risetime < 0.02;
$risetime = $pulsems/4000 if $risetime > $pulsems/4000;
$risecnt = $risetime * $bitrate;

#$charpause = 12000 * (1/$effwpm - 1/$wpm);
$extracharms = 60000 / 7 * (1 / $effwpm - 1 / $wpm);
$extracharms = 0 unless $extracharms > 0;
$charpause = $pulsems * 2 + $extracharms;


print "WPM=$wpm, Effective WPM=$effwpm, pulsems=$pulsems, risetime=$risetime, charpause=$charpause\n";

$dotbeep = Audio::Data->new(rate=>$bitrate);
$dotduration = 0.001 * $pulsems + $risetime; # time start/stop from "half amplitude" points
$dotbeep->tone($tonefreq * $ratecorrection, $dotduration / $ratecorrection, 0.5);

@dotbeepdata = $dotbeep->data;
$dotsamples = scalar(@dotbeepdata);

for ($i = 0; $i < $risecnt; $i++) {
   $dotbeepdata[$i] *= ($i / $risecnt);
   $dotbeepdata[$dotsamples-$i-1] *= ($i / $risecnt);
}

$dotbeep->data(@dotbeepdata);

$dashbeep = Audio::Data->new(rate=>$bitrate);
$dashduration = 0.001 * $dashweight * $pulsems + $risetime;
$dashbeep->tone($tonefreq * $ratecorrection, $dashduration / $ratecorrection, 0.5);

@dashbeepdata = $dashbeep->data;
$dashsamples = scalar(@dashbeepdata);

for ($i = 0; $i < $risecnt; $i++) {
   $dashbeepdata[$i] *= ($i / $risecnt);
   $dashbeepdata[$dashsamples-$i-1] *= ($i / $risecnt);
}

$dashbeep->data(@dashbeepdata);

$dotsilence = Audio::Data->new(rate=>$bitrate);
$dotsilenceduration = 0.001 * $pulsems - $risetime;
$dotsilence->silence($dotsilenceduration / $ratecorrection);

my $wholedot = $dotbeep . $dotsilence;
my $wholedash = $dashbeep . $dotsilence;

$charsilence = Audio::Data->new(rate=>$bitrate);
$charsilenceduration = 0.001 * $charpause;
$charsilence->silence($charsilenceduration / $ratecorrection);

$bufferclearsilence = Audio::Data->new(rate=>$bitrate);
$bufferclearsilenceduration = 0.2;
$bufferclearsilence->silence($bufferclearsilenceduration / $ratecorrection);

# get actual durations allowing for any rounding
my $wholedotduration = $wholedot->duration * $ratecorrection;
my $wholedashduration = $wholedash->duration * $ratecorrection;
my $charsilenceduration = $charsilence->duration * $ratecorrection;
my $bufferclearduration = $bufferclearsilence->duration * $ratecorrection;

printf("Sample durations: wholedot=%6.3f wholedash=%6.3f chargap=%6.3f\n",
   $wholedotduration, $wholedashduration, $charsilenceduration);

#@d = $dotbeepseq->data;
#foreach (@d) {printf "%7.4f\n", $_} ;

#exit;

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
      clearbuffer(); # allow to flush
      # record a notional end time of an interword space
      my $notionalplayendtime = $expectedplayendtime + $charsilenceduration * 2;
      push @charendtimereports, " \t$notionalplayendtime\t4\n";
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
    $expectedplayendtime += $wholedotduration;
    $pulses += 2;
}

sub playdash {
    print '-' if $verbose;
    safeplay($svr, $wholedash);
    $expectedplayendtime += $wholedashduration;
    $pulses += ($dashweight + 1);
}

sub playspace {
    print '_'  if $verbose;
    safeplay($svr, $charsilence);
    $expectedplayendtime += $charsilenceduration;
    $pulses += 2;
}

sub clearbuffer {
    print '|'  if $verbose;
    safeplay($svr, $bufferclearsilence);
    $expectedplayendtime += $bufferclearduration;
}

