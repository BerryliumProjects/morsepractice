package TestWord;
use strict;
use warnings;

use Data::Dumper;
use IO::Handle;
use Time::HiRes qw(time usleep);

# /var/tmp is on a tmpfs; /tmp is not
my $mp2readyfile = '/var/tmp/mp2ready.txt';
unlink($mp2readyfile) if -f $mp2readyfile;

my $mp2statsfile = '/var/tmp/mp2stats.txt';

my $starttime;
my $successes;
my $prevspacetime = 0;

my $pulsecount = 0;
my $totalcharcount = 0; # includes spaces
my $nonblankcharcount = 0;
my %badchars;
my $badcharcnt = 0;
my $missedcharcnt = 0; # where short word entered
my $userword = '';
my $tgtword = '';
my $prevword = '';

my $pulsetime;
my $extracharpausetime;

my @chtimes = ();

my @alluserinput = ();
my $userwordcnt;
my $testwordcnt;
my @userwordinput;
my @testwordstats;

my %histogram = (); # frequency of characters used
my %reactions = (); # cumulative reaction time for each character
my %histogram2 = (); # frequency of character position
my %reactions2 = (); # cumulative reaction time for each character position
my @positioncnt = (); # characters to recognise by position in word
my @positionsuccess = (); # characters correctly identified by position in word
 
  $successes = 0;
   $pulsecount = 0;
   $totalcharcount = 0;
   $nonblankcharcount = 0;
   $automode = 1;
   $badcharcnt = 0;
   $missedcharcnt = 0;
   %badchars = ();
   $abortpending = 0;
   $prevspacetime = 0;
   @alluserinput = ();
   @userwordinput = ();
   $userwordcnt = 0;
   $testwordcnt = 0;

   %histogram = (); 
   %reactions = ();
   %histogram2 = (); 
   %reactions2 = ();
   @positioncnt = ();
   @positionsuccess = ();
    
   $starttime = time();
 
   if ($e->{syncafterword}) {   
      autogen();
   } else {
      my $testtext = generateText();
      my @testtext = split(/ /, $testtext);     
      $testwordcnt = scalar(@testtext); # target word count
      print MP "$testtext\n";
   }
}

sub new {
   # word including trailing space character and additional attributes
   my $class = shift;
   my $tw = {};
   bless($tw, $class);
   $tw->init;
   return $tw;
}

sub init {
   my $tw = shift;
   my @endtimes = ();
   my @pulsecnts = ();
   $tw->{word} = '';
   $tw->{pulsecnts} = \@pulsecnts;
   $tw->{endtimes} = \@endtimes;
}

sub bareword {
   my $tw = shift;
   my $word = $tw->{word};
   $word =~ s/ //g;
   return $word;
}

sub length {
   my $tw = shift;
   return length($tw->{word});
}

sub add {
   my $tw = shift;
   my $key = shift;
   my $pulses = shift;
   my $time = shift;
  
   $tw->{word} .= $key;
   push (@{$tw->pulsecnts}, $pulses);
   push (@{$tw->{endtimes}, $time);
}

sub undo {
   my $tw = shift;
   my $w = $tw->{word};
   my $l = length($w);

   if ($l > 0) {
      $tw->{word} = substr($w, 0, $l - 1);
      pop(@{$tw->{endtimes}});
      pop(@{$tw->{pulsecnts}});
      
   }
}

sub export {
# create serialised representation of test word state
   my $tw = shift;
   my $ser = '';

   for (my $i=0; $i < $tw->length; $i++) {
      $ser .= substr($tw->{word, $i, 1) . "\t" . $tw->{endtimes}->[$i] . "\t" . $tw->{pulsecnt}->[$i] . "\n";
   }
 
   return $ser;
}

sub import {
# build test word from serialised representation, line by line
   my $tw = shift;
   my $line = shift;

   chomp $line;

   my ($char, $time, pulses) = split(/\t/, $line);

   if (defined($char) and defined($time)) {
      $tw->{word} .= $char;
      push(@{$tw->pulsecnts}, $pulses;
      push(@{$tw->endtimes}, $time);
   }

   return (defined($char) and ($char ne ' '); # indicate if more to read
}
 
sub align {
   my $uw = shift;
   my $tw = shift;

   my $testlen = $tw.length;
   my $userlen = $uw.length;
   my $userword = $uw->{word};

   my $difpos;

   if ($userlen < $testlen) {
      # user has missed some characters - find first mismatch
      for ($difpos = 0; $difpos < $userlen; $difpos++) {
         last if (substr($tw->{word}, $difpos, 1)  ne substr($userword, $difpos, 1));
      }

      my $aligneduw = '';
      # assume first mismatch is really a gap, and fill it
      for ($userlen .. $testlen - 1) {
         if ($difpos > 0) {
            $aligneduw =  substr($userword, 0, $difpos - 1);
         }

         $aligneduw .= '_' . substr($userword, -$difpos); # rest of string
         $uw->{word} = $aligneduw;
         splice(@{$uw->{keytimes}}, $difpos, 0, 0); # no time recorded
      }
   }
}

sub checkchar {
   my $obj = shift; # automatically supplied reference to callback sender
   my $ch = shift;
   # updates $userwordx and writes to <USERIN>
   # if syncing after each word and retrying mistakes, also refers to $latesttestword 

   return unless ($automode);

   $ch = lc($ch);
   $ch =~ s/\r/ /; # newline should behave like space as word terminator

   if ($ch ne '') { # ignore empty characters (e.g. pressing shift)
      my $thischtime = time();
      my $duration = time() - $starttime;

      if ($ch eq "\b") {
         if ($e->{allowbackspace}) {
            $userwordx->undo;
         }
      } else {
         if ($ch eq ' ') {
            # ignore a double space if less than a second between them
            if (($userwordx->length == 0) and ($thischtime < $prevspacetime + 1)) {
               $ch = '';
            } else {
               $userwordx->add($ch, $thischtime);
            }

            $prevspacetime = $thischtime;
         } else {
            $userwordx->add($ch, $thischtime);

            if ($e->{maxwordlength} == 1) { # fill in the end of word blank
               $userwordx->add(' ', $thischtime);
            }
         }
      }

      if (($e->{maxwordlength} == 1) or $ch eq ' ') {
         if ($e->{syncafterword}) { 
            # get word report from player
            syncflush();

            open (STATS, $mp2statsfile);
            $testwordx = TestWord->new;
            while ($testwordx->import(<STATS>) {};
            close(STATS);
            unlink($mp2statsfile);

            $testwordcnt++; # length of test is variable depending on progress in test duration
            $userwordx->align($testwordx);

            markword($userwordx, $testwordx);
            $userword = $userwordx->bareword;
            $testword = $testwordx->bareword;

            $userwordx->init;

            my $outoftime = ($e->{practicetime} > 0 and ($e->{practicetime} * 60) < $duration);

            if ($userword eq $testword) {
               $successes++;

               if ($outoftime) {
                  $abortpending = 1;
               } else {
                  autogen();
               }
            } else {
               if ($e->{retrymistakes} and not $abortpending) {
                  playword($testword); ## req extra trailing space?
                  $d->insert('end', '# ');
                  $testwordcnt--; # retried word doesn't count as a new word
               } else {
                  $d->insert('end', "# [$testword] "); 
                  if ($outoftime or $abortpending) {
                     stopAuto();
                  } else {
                     autogen();
                  }
               }
            }
         } else {
            $userwordcnt++;
            $alluserinput .= $userwordx->export;
            $userwordx->init;

            if ($userwordcnt >= $testwordcnt) {
               stopAuto();
            } 
         }
      }
   }

   if ($abortpending) {
      stopAuto();
   }
}

sub markword {
   # find characters in error and mark reactions
   # words need to be aligned for best fit first
   my $userwordx = shift;
   my $testwordx = shift;

   for (my $i = 0; $i < $testwordx->length; $i++) {
      my $userchar = substr($userwordx->{word}, $i, 1);
      my $testchar = substr($testwordx->{word}, $i, 1);
      my $endchartime = $testwordx->{endtimes}->[$i];
      my $testpulsecnt = $testwordx->{pulsecnt}->[$i];
      my $testcharduration = $testpulsecnt * $pulsetime;
      my $usertime = $userwordx->{endtimes}->[$i];
      my $reaction = $usertime - $endchartime;

      $pulsecount += $testpulsecnt; # for  whole session
      $totalcharcount++; # count spaces as chars

      if ($testchar ne ' ') {
         $nonblankcharcount++;
 
         if ($userchar eq '_') { # missed char
	    $missedcharcnt++;
 	    $badchars{$testchar} = 1;

	    # increase frequency of confused characters for later
            # any invalid characters will be played as = 
	    $autoextraweights .= $testchar . $testchar;
         } elsif ($userchar ne $testchar) {
	    $badcharcnt++;

	    # increase frequency of confused characters for later
            # any invalid characters will be played as = 
	    $autoextraweights .= $userchar . $testchar . $testchar;
            $badchars{$testchar} = 1;
         } 

         if (exists $positionsuccess[$i]) {
            $positioncnt[$i]++;
            $positionsuccess[$i] += ($userchar eq $testchar);
         } else {
            $positioncnt[$i] = 1;
            $positionsuccess[$i] = ($userchar eq $testchar);
         }
      }

      # allow for missing tgttime
      if ($reaction >= -8) {
         my $reactionms = int($reaction * 1000 + 0.5);

         my $histcharindex = ($testchar eq ' ') ? '>' : $testchar; # for legibility
         my $histposindex = ($testchar eq ' ') ? -1 : $i; # notional index for word gap
         my $testchardurationms = int($testcharduration * 1000 + 0.5);
	 print "$testchar ($testchardurationms), $userchar, $reactionms\n";

         if ($e->{measurecharreactions}) {
            if (exists $histogram{$histcharindex}) {
	       $histogram{$histcharindex}++;
               $reactions{$histcharindex} += $reaction;
            } else {
 	       $histogram{$histcharindex} = 1;
	       $reactions{$histcharindex} = $reaction;
	    }
         }
     
         # also record reaction/histogram by position in word
         if ($e->{measurecharreactions} or $histposindex < 0) {
            if (exists $histogram2{$histposindex}) {
	       $histogram2{$histposindex}++;
	       $reactions2{$histposindex} += $reaction;
	    } else {
	       $histogram2{$histposindex} = 1;
	       $reactions2{$histposindex} = $reaction;
	    }
         }
      } else {
         print "$testchar, $userchar\n";
      }         
   }

   # if in word recognition mode, note reaction time to start entering word
   if (not $e->{measurecharreactions}) {
      my $startuserwordtime = 0;

      for (my $i = 0; $i < $userinputx->length; $i++) {
         # note when user started to respond
         $startuserwordtime = $userinputx->{keytimes}->[$i] unless $startuserwordtime;
      }

      my $wordreaction = $startuserwordtime - $testwordx->{keytimes}->[-2]; # index -2 is last character before terminating blank

      if (exists $histogram2{-2}) {
         $histogram2{-2}++;
         $reactions2{-2} += $wordreaction;
      } else {
         $histogram2{-2} = 1;
         $reactions2{-2} = $wordreaction;
      }
 
      printf "Word:  %i\n",  $wordreaction * 1000 + 0.5;
   }

   return ($userword, $testword);
}

sub marktest {

   $d->Contents(''); # clear the text display

   # get test report from player
   open (STATS, $mp2statsfile);
   my $userwordx = TestWord->new;
   my $testwordx = TestWord->new;

   my @alluserinput = split(/\n/, $alluserinput);

   for (my $iw = 0; $iw < $testwordcnt; $iw++) {
      $userwordx->init;
      while ($userwordx->import(shift(@alluserinput))) {};
  
      $testwordx->init;
      while ($testwordx->import(<STATS>)) {};

      $userwordx->align($testwordx);

      markword($userwordx, $testwordx);
      my $userword = $userwordx->bareword;
      my $testword = $testwordx->bareword;

      if ($userword eq $testword) {
         $successes++;
         $d->insert('end', "$testword ");
      } else {
         $d->insert('end', "$userword # [$testword] "); 
      }
   }

   close(STATS);
   unlink($mp2statsfile);
}


