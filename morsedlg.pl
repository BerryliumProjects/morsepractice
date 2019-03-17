#! /usr/bin/perl 
use strict;
use warnings;

use Tk;
use Tk::ROText;

use Data::Dumper;
use Tk::After;
use IO::Handle;
use Time::HiRes qw(time usleep);

use charcodes; # definitions of characters as dit-dah sequences
our %charcodes;

use dialogfields;
use testwordgenerator;

my $twg; # instance of test word generator
# /var/tmp is on a tmpfs; /tmp is not
my $mp2readyfile = '/var/tmp/mp2ready.txt';
unlink($mp2readyfile) if -f $mp2readyfile;

my $mp2pidfile = '/var/tmp/mp2pid.txt';
unlink($mp2pidfile) if -f $mp2pidfile;

my $mp2statsfile = '/var/tmp/mp2stats.txt';
# my $homedir = "/home/berry/Documents/m2";
my $morseplayer = "./morseplayer2.pl"; 

my $starttime;
my $duration;
my $successes;
my $autoextraweights = '';
my $abortpendingtime = 0;
my $userabort = 0;
my $prevspacetime = 0;

my $pulsecount = 0;
my $totalcharcount = 0; # includes spaces
my $nonblankcharcount = 0;
my $userword = '';
my $testword = '';
my $prevword = '';

my $pulsetime;
my $extracharpausetime;

my @alluserinput = ();
my $userwordcnt;
my $testwordcnt;
my @userwordinput;
my @testwordstats;

my @subdictionary;

# histograms
my $reactionsbychar;
my $reactionsbypos;
my $missedchars;
my $mistakenchars;
my $successbypos;

my $wpm = $ARGV[0];

(defined $wpm and $wpm > 0 ) or
   $wpm = 20;

my $effwpm = $ARGV[1];

(defined $effwpm and $effwpm > 0) or
   $effwpm = $wpm;

my $pitch = $ARGV[2];

(defined $pitch and $pitch > 0) or
   $pitch = 600;

my $weightedkeylist; # can include repeats of common characters

my $automode; # if set then each keypress is checked against the previously generated character.
my $prevauto = ''; # If entered key matches this then another random character is generated, otherwise the last one is repeated

my $w = MainWindow->new();

my $font = $w->fontCreate('msgbox',-family=>'helvetica', -size=>-14);
#print "Actual font:" .  Dumper($w->fontActual('msgbox')) . "\n";
#printf "Descent/Linespace: %i %i\n", $w->fontMetrics('msgbox', -descent), $w->fontMetrics('msgbox', -linespace); 


# share as global variables for general access
my $mwdf = DialogFields->init($w);
my $e = $mwdf->entries; # gridframe control values
my $d; # exercisetext control ref, set by populatemainwindow
populatemainwindow();
setdictsizes(); # based on what dictionaries have been selected
validateSettings();

$w->MainLoop();

### print "\n";
sub populatemainwindow {
   my $knownchars = join('', sort keys(%charcodes));
   $knownchars =~ s/ //; # remove blank as an option

   $mwdf->addEntryField('Characters to practice', 'keylist', 40, $knownchars, undef, sub{setexweights()}, '');
   $mwdf->addEntryField('Practice session time (mins)', 'practicetime', 40, 2, undef, undef, '');
   $mwdf->addEntryField('Min Word Length', 'minwordlength', 40, 1, undef, sub{setdictsizes()}, '');
   $mwdf->addEntryField('Max Word Length', 'maxwordlength', 40, 9, undef, sub{setdictsizes()}, '');
   $mwdf->addEntryField('Character WPM', 'wpm', 40, $wpm, 'w', undef, '');
   $mwdf->addEntryField('Effective WPM', 'effwpm', 40, $effwpm, undef, undef, '');
   $mwdf->addEntryField('Note Pitch', 'pitch', 40, $pitch, undef, undef, '');
   $mwdf->addEntryField('Playing rate factor', 'playratefactor', 40, '1.00', undef, undef, '');
   $mwdf->addEntryField('Dash Weight', 'dashweight', 40, 3, undef, undef, '');
   $mwdf->addEntryField('Extra word spaces', 'extrawordspaces', 40, 0, undef, undef, '');

   $mwdf->addCheckbuttonField('Allow backspace', 'allowbackspace',  1, undef, undef, '');
   $mwdf->addCheckbuttonField('Use relative frequencies', 'userelfreq',  1, undef, sub{setexweights()}, '');
   $mwdf->addCheckbuttonField('Sync after each word', 'syncafterword',  1, undef, undef, '');
   $mwdf->addCheckbuttonField('Retry mistakes', 'retrymistakes',  0, undef, undef, '');
   $mwdf->addCheckbuttonField('Use Random Sequences', 'userandom',  1, undef, sub{setdictsizes()}, '');
   $mwdf->addCheckbuttonField('Use Pseudo Words', 'usepseudo',  0, undef, sub{setdictsizes()}, '');
   $mwdf->addCheckbuttonField('Use English Dictionary', 'useedict',  0, undef, sub{setdictsizes()}, '');
   $mwdf->addCheckbuttonField('Use QSO Dictionary', 'useqdict',  0, undef, sub{setdictsizes()}, '');
   $mwdf->addCheckbuttonField('Measure character reaction times', 'measurecharreactions',  1, undef, undef, '');

   $mwdf->addEntryField('Word list size', 'wordlistsize', 40, 0, undef, undef, 'locked');
   $mwdf->addEntryField('Dictionary Sample Size', 'dictsize', 40, 9999, undef, undef, '');
   $mwdf->addEntryField('Dictionary Sample Offset', 'dictoffset', 40, 0, undef, undef, '');
   $mwdf->addEntryField('Extra Character Weights', 'xweights', 40, '', undef, sub{setdictsizes()}, '');


   $d = $mwdf->addWideTextField(undef, 'exercisetext', 8, 50, '', undef, undef, '');
   $d->focus;
   $d->bind('<KeyPress>', [\&checkchar, Ev('A')]); # automatically supplies a reference to $d as first argument

   $mwdf->addButtonField('Calibrate', 'calibrate',  'c', sub{calibrate()}, '');
   $mwdf->addButtonField('AutoWeight', 'autoweight',  'u', sub{autoweight()}, '');
   $mwdf->addButtonField('Start', 'start',  's', sub{startAuto()}, '');
   $mwdf->addButtonField('Generate', 'generate',  'g', sub{validateSettings(); $d->Contents(generateText())}, '');
   $mwdf->addButtonField('Play', 'play',  'p', sub{playText($d->Contents)}, '');
   $mwdf->addButtonField('Quit', 'quit',  'q', sub{if ($automode) {abortAuto()} else {$w->destroy}}, '');

   setexweights();
}

sub setexweights {
   if ($e->{userelfreq}) {
      $e->{xweights} = TestWordGenerator->plainEnglishWeights($e->{keylist}); 
   } else {
      $e->{xweights} = '';
   }
}

sub validateSettings {
   $pulsetime = 1.2 / $e->{wpm}; # a dit-mark or gap
   $extracharpausetime = 60 / 7 * (1 / $e->{effwpm} - 1 / $e->{wpm});
   $weightedkeylist = $e->{keylist} . $e->{xweights};
   $autoextraweights = ''; 

   if (not $e->{minwordlength}) { # check if numeric and > 0
      $e->{minwordlength} = 1;
   }

   if ((not $e->{maxwordlength}) or ($e->{maxwordlength} < $e->{minwordlength})) {
      $e->{maxwordlength} = $e->{minwordlength};
   }

   $twg = TestWordGenerator->new($e->{minwordlength}, $e->{maxwordlength});

   # build selected word list considering complexity and min/max word length
   @subdictionary = ();

   if ($e->{retrymistakes}) {
      $e->{syncafterword} = 1; # 'can't retry unless syncing after each word
   }

   unless ($e->{useqdict} or $e->{useedict} or $e->{userandom}) {
      $e->{usepseudo} = 1; # ensure at least some words added
   }

   if ($e->{userandom}) {
      $twg->addRandom($weightedkeylist, 200);
   }

   if ($e->{usepseudo}) {
      $twg->addPseudo(200);
   }

   if ($e->{useqdict}) {
      $twg->addDictionary('qsolist.txt', $e->{dictoffset}, $e->{dictsize});
      $e->{userelfreq} = 0; # incompatible with using dictionary
   }

   if ($e->{useedict}) {
      $twg->addDictionary('wordlist.txt', $e->{dictoffset}, $e->{dictsize});
      $e->{userelfreq} = 0; # incompatible with using dictionary
   }

   $e->{wordlistsize} = $twg->{size};
}


   
sub startAuto {
   validateSettings();

   open(MP, "|  perl $morseplayer " . join(' ', $e->{wpm}, $e->{effwpm}, $e->{pitch}, $e->{playratefactor}, $e->{dashweight}, $e->{extrawordspaces})) or die; 
   autoflush MP, 1;

   $d->Contents('');
   $d->focus;
   setControlState('disabled');
   $successes = 0;
   $pulsecount = 0;
   $totalcharcount = 0;
   $nonblankcharcount = 0;
   $automode = 1;
   $abortpendingtime = 0;
   $prevspacetime = 0;
   @alluserinput = ();
   @userwordinput = ();
   $userwordcnt = 0;
   $testwordcnt = 0;
   $userword = '';

   $reactionsbychar = {};
   $reactionsbypos = {};
   $missedchars = {};
   $mistakenchars = {};
   $successbypos = {};
 
   print MP "= \n";
   sleep 2;
   syncflush();
   unlink($mp2statsfile);

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

sub generateWord {
    $prevword = $twg->chooseWord($prevword);
    return $prevword;
}

sub autogen {
   $testword = generateWord();
   playword($testword);
}

sub abortAuto {
   $abortpendingtime = time();
   $userabort = 1;
   checkchar(' ');
}

sub checkchar {
   my $obj = shift; # automatically supplied reference to callback sender
   my $ch = shift;

   return unless ($automode);
   $duration = time() - $starttime;

   $ch = lc($ch);
   $ch =~ s/\r/ /; # newline should behave like space as word terminator

   if ($ch ne '') { # ignore empty characters (e.g. pressing shift)
      my $thischtime = time();

      if ($ch eq "\b") {
         if ($e->{allowbackspace} and $userword ne '') {
            # discard final character and stats 
            pop(@userwordinput);
            $userword = substr($userword, 0, -1);
         }
      } else {
         if ($ch eq ' ') {
            # ignore a double space if less than 500ms between them
            if ((scalar(@userwordinput) == 0) and ($thischtime < $prevspacetime + 0.5)) {
               $ch = '';
            } else {
               push(@userwordinput, "$ch\t$thischtime\n");
            }

            $prevspacetime = $thischtime;
         } else {
            push(@userwordinput, "$ch\t$thischtime\n");
            $userword .= $ch;

            if ($e->{maxwordlength} == 1) { # fill in the end of word blank
               push(@userwordinput, " \t$thischtime\n");
            }
         }
      }

      if (($e->{maxwordlength} == 1) or $ch eq ' ') {
         chomp(@userwordinput);
         push(@alluserinput, @userwordinput);
         @userwordinput = ();

         if ($e->{syncafterword}) { 
            # get word report from player
            syncflush();

            $testwordcnt++; # length of test is variable depending on progress in test duration

            if ($e->{practicetime} > 0 and ($e->{practicetime} * 60) < $duration) {
               $abortpendingtime = time(); 
            } else {
               if (($userword ne $testword) and $e->{retrymistakes}) {
                  playword($testword); ## req extra trailing space?
                  $d->insert('end', '# ');
               } else {
                  autogen();
               }
            }
         } else {
            $userwordcnt++;

            if ($userwordcnt >= $testwordcnt) {
               $abortpendingtime = time();
            } 
         }

         $userword = '';
      }
   }

   if ($abortpendingtime) {
      stopAuto();
   }
}

sub alignchars {
   # if user entry is too short, insert blanks to realign to correct length
   my $userinputref = shift;
   my $teststatsref = shift;

   my $testlen = scalar(@$teststatsref);
   my $userlen = scalar(@$userinputref);

   my $difpos = 0;	 
   
   if ($userlen < $testlen) {
      # user has missed some characters - find first mismatch
      for ($difpos = 0; $difpos < $userlen; $difpos++) { 
         last if ($userinputref->[$difpos]->{ch} ne $teststatsref->[$difpos]->{ch});
      }

      # assume first mismatch is really a gap, and fill it
      for ($userlen .. $testlen - 1) {
         splice @$userinputref, $difpos, 0, {ch => '_', t => 0}; # no time recorded
      }
   }
}

sub buildhistogram {
   # add values to a histogram accumulator
   my $histogram = shift;
   my $key = shift;
   my $value = shift;

   if (exists $histogram->{count}->{$key}) {
      $histogram->{count}->{$key}++;
      $histogram->{total}->{$key} += $value;
   } else {
      $histogram->{count}->{$key} = 1;
      $histogram->{total}->{$key} = $value;
   }
}

sub counthistogram {
   # get number of items added to histogram
   my $histogram = shift;

   my $count = 0;

   foreach my $key (keys %{$histogram->{count}}) {
      $count += $histogram->{count}->{$key};
   }
   
   return $count;
}

sub gethistogramaverages {
   # return a reference to a hash of average values (total/count)
   my $histogram = shift;

   my $averages = {};

   foreach my $key (keys %{$histogram->{count}}) {
      # count is always at least 1, or the key would not exist
      $averages->{$key} = $histogram->{total}->{$key} / $histogram->{count}->{$key};
   }

   return $averages;
}

sub markword { 
   # find characters in error and mark reactions
   my $userinputref = shift;
   my $teststatsref = shift;

   my $testlen = scalar(@$teststatsref);

   my $startuserwordtime = 0;
   my $endtestwordtime = 0;
   my $markuserword = '';
   my $marktestword = '';
   my $prevusertime; # initially undef
 
   for (my $i = 0; $i < $testlen; $i++) {
      my $userinput = $userinputref->[$i];
      my $teststatsitem = $teststatsref->[$i];

      my $userchar = $userinput->{ch};
      my $testchar = $teststatsitem->{ch};
      my $endchartime = $teststatsitem->{t};
      my $testpulsecnt = $teststatsitem->{pcnt};

      my $testcharduration = $testpulsecnt * $pulsetime;
      my $usertime = $userinput->{t};
      my $reaction = $usertime - $endchartime;

      my $typingtimems = '';

      if (defined $prevusertime and $prevusertime > 0 and $usertime > 0) {
         $typingtimems = int(($usertime - $prevusertime) * 1000);
      }

      $prevusertime = $usertime;

      $pulsecount += $testpulsecnt; # for  whole session
      $totalcharcount++; # count spaces as chars

      if (not $e->{measurecharreactions}) {
         # note when user started to respond and when end of word was detectable
         $startuserwordtime = $usertime unless $startuserwordtime;
         $endtestwordtime = $endchartime;
      }

      $markuserword .= $userchar unless $userchar eq ' ';
      $marktestword .= $testchar unless $testchar eq ' ';

      if ($testchar ne ' ') {
         $nonblankcharcount++;
 
         if ($userchar eq '_') { # missed char
            buildhistogram($missedchars, $testchar, 1);

	    # increase frequency of confused characters for later
            # any invalid characters will be played as = 
	    $autoextraweights .= $testchar . $testchar;
            buildhistogram($successbypos, $i, 0);
         } elsif ($userchar ne $testchar) {
            buildhistogram($mistakenchars, $testchar, 1);	    

	    # increase frequency of confused characters for later
            # any invalid characters will be played as = 
	    $autoextraweights .= $userchar . $testchar . $testchar;
            buildhistogram($successbypos, $i, 0);
         } else { 
            buildhistogram($successbypos, $i, 1); 
         }
      }

      # allow for missing tgttime
      if ($reaction >= -8) {
         my $reactionms = int($reaction * 1000 + 0.5);
         my $histcharindex = ($testchar eq ' ') ? '>' : $testchar; # for legibility
         my $histposindex = ($testchar eq ' ') ? -1 : $i; # notional index for word gap
         my $testchardurationms = int($testcharduration * 1000 + 0.5);
	 print "$testchar ($testchardurationms), $userchar, $reactionms, $typingtimems\n";

         if ($e->{measurecharreactions}) {
            buildhistogram($reactionsbychar, $histcharindex, $reaction);
         }

         # also record reaction/histogram by position in word (key:tab-n)
         if ($e->{measurecharreactions} or $histposindex < 0) {
            buildhistogram($reactionsbypos, $histposindex, $reaction);
         }
      } else {
         print "$testchar, $userchar\n";
      }         
   }

   # if in word recognition mode, note reaction time to start entering word
   if (not $e->{measurecharreactions}) {
      my $wordreaction = $startuserwordtime - $endtestwordtime;

      if ($wordreaction > -3 and $wordreaction < 3) { # ignore if either time is missing
         buildhistogram($reactionsbypos, -2, $wordreaction);

         printf "Word:  %i\n",  $wordreaction * 1000 + 0.5;
      }
   }

   if ($markuserword eq $marktestword) {
      $successes++;
      $d->insert('end', "$marktestword ");
   } else {
      $d->insert('end', "$markuserword # [$marktestword] "); 
   }
}

sub marktest {
   $d->Contents(''); # clear the text display

   # get test report from player
   open (STATS, $mp2statsfile);
   my @teststats = <STATS>;
   close(STATS);
   unlink($mp2statsfile);

   chomp @teststats;
   chomp @alluserinput;

   my @userwords = ();
   my @testwords = ();

   for (my $iw = 0; $iw < $testwordcnt; $iw++) {
      my $userwordinput = [];
      
      while (defined (my $userinput = shift(@alluserinput))) {  
         my ($userchar, $usertime) = split(/\t/, $userinput);
         my $userrec = {ch => $userchar, t => $usertime};
         push(@{$userwordinput}, $userrec);
         last if ($userchar eq ' ');
      }
  
      my $testwordstats = [];

      my $testwordendtime = 0;

      while (defined (my $teststatsitem = shift(@teststats))) {
         my ($testchar, $testtime, $testpulsecnt) = split(/\t/, $teststatsitem);
         my $testrec = {ch => $testchar, t => $testtime, pcnt => $testpulsecnt};
         push(@{$testwordstats}, $testrec);

         if ($testchar eq ' ') {
            ($testwordendtime) = $testtime;
            last;
         }
      }

      # if exercise was terminated early, ignore any test content after that time
      # don't abort if on last word of exercise - a quick user response could abort the last word
      last if ($abortpendingtime > 0 and $iw < $testwordcnt - 1 and $testwordendtime > $abortpendingtime);

      push(@userwords, $userwordinput);
      push(@testwords, $testwordstats);
   }

   # re-align words in case user missed a space - TO-DO

   for (my $iw = 0; $iw < scalar(@testwords); $iw++) {
      # re-align characters in words in case some missed
      alignchars($userwords[$iw], $testwords[$iw]);
      markword($userwords[$iw], $testwords[$iw]);
   }
}

sub playword {
   my $word = shift;

   if ($e->{maxwordlength} == 1) {
      playchar($word);
   } else {
      # play all characters in word plus 2 spaces
      foreach my $ch (split(//, $word)) {
         playchar($ch);
      }
   }

   print MP "\n";
}

sub playText {
   my $ptext = shift;

   open(MP, "|  perl $morseplayer " . join(' ', $e->{wpm}, $e->{effwpm}, $e->{pitch}, $e->{playratefactor}, $e->{dashweight}, $e->{extrawordspaces}, '-t')) or die; 
   autoflush MP, 1;

   print MP "=   $ptext\n#\n";
   close(MP);
}

sub generateText {
   my $avgwordlength = ($e->{maxwordlength} + $e->{minwordlength}) / 2;
   ($avgwordlength > 1) or ($avgwordlength = 5);
  
   # the space at the end of a word is approximately half an average character in duration
   my $genwords = $e->{practicetime} * $e->{effwpm} * 5.5 / ($avgwordlength + 0.5 * (1 + int($e->{extrawordspaces})));

   my $text = '';

   for (my $i = 0; $i < $genwords; $i++) {
      $text .= generateWord() . ' ';
   }

  chop($text); # remove final blank 
  return $text;
}

sub calibrate {
   # Play a standard tune-up message at "A" pitch and 20 wpm

   open(MP, "|  perl $morseplayer " . join(' ', 20, 20, 440, $e->{playratefactor}, 3, 0)) or die; 
   autoflush MP, 1;

   print MP "000 cq cq\n#\n";
   close(MP);

   # now play a standard message at the selected pitch and wpm 
   open(MP, "|  perl $morseplayer " . join(' ', $e->{wpm}, $e->{effwpm}, $e->{pitch}, $e->{playratefactor}, $e->{dashweight}, $e->{extrawordspaces})) or die;

   autoflush MP, 1;

   print MP "paris paris\n#\n";
   close(MP);
}

sub playchar {
   my $ch = shift;

   if (defined($ch) and length($ch) == 1) {
      print MP $ch;
      my $chseq = $charcodes{lc($ch)};

      if (defined $chseq) {
         my @chseqelements = split('', $chseq);

         my $pulses = 0; 

         for (my $i = 0; $i < scalar(@chseqelements); $i++) {
            if ($chseqelements[$i] eq '-') {
               $pulses += ($e->{dashweight} + 1);
            } else {
               $pulses += 2;
            }
         }
      }
   }
}

sub stopAuto {
   $automode = 0;

   if (not $userabort) {
      print MP "#\n";
   } else {
      open(PIDFILE, $mp2pidfile);
      my $mp2pid = <PIDFILE>;
      chomp($mp2pid);

      kill('SIGTERM', $mp2pid); # ask player to terminate early
      unlink($mp2pidfile);
   }   

   close(MP);

   syncflush();

   if ($starttime > 0) {
      marktest();
      showresults();
      $starttime = undef;
   }

   setControlState('normal');

   if ($e->{dictsize} == 0) {
      $e->{dictsize} = 9999; # avoid lock ups 
   }

   unlink($mp2readyfile) if -f $mp2readyfile;
}

sub showresults {
   my $rw = $w->Toplevel(-title=>'Results'); # results window
   my $rwdf = DialogFields->init($rw);
   populateresultswindow($rwdf);

   # statistics used: 
   #   words:  testwordcnt, successes
   #   chars:  nonblankcharcount, totalcharcount, mistakenchars, missedchars
   #   pulses: pulsecount
   #   reactions: reactionsbychar, reactionsbypos - reactions recorded for bad chars but not missed chars

   my $successrate = ($testwordcnt ? $successes / $testwordcnt : 0);
   my $missedcharcnt = counthistogram($missedchars);
   my $mistakencharcnt = counthistogram($mistakenchars);
   my $charsuccessrate = ($nonblankcharcount ? 1 - ($missedcharcnt + $mistakencharcnt) / $nonblankcharcount : 0);
   my $avgpulsecnt = ($totalcharcount ? $pulsecount / $totalcharcount : 0);

   my $re = $rwdf->entries; # gridframe control values
   $re->{duration} = sprintf('%i', $duration);
   $re->{wordreport} = sprintf('%i%% (%i / %i)', $successrate * 100, $successes, $testwordcnt);
   $re->{charreport} = sprintf('%i%% (%i missed, %i wrong / %i)', $charsuccessrate * 100, $missedcharcnt, $mistakencharcnt, $nonblankcharcount);
   $re->{missedchars} = join('', sort(keys(%{$missedchars->{count}})));
   $re->{mistakenchars} = join('', sort(keys(%{$mistakenchars->{count}})));
   $re->{pariswpm} = sprintf('%.1f', ($pulsecount / 50) * $charsuccessrate / ($duration / 60)); # based on elements decoded
   $re->{charswpm} = sprintf('%.1f', ($e->{effwpm} * $charsuccessrate)); # based on characters decoded
   $re->{relcharweight} = sprintf('%i%%', $avgpulsecnt / (50 / 6) * 100); # as percentage
   $re->{charpausefactor} = sprintf('%i%%', $extracharpausetime / $pulsetime / 2 * 100); # as percentage
 
 
   # Report slowest average reaction times by character
   my %avgreactionsbychar = %{gethistogramaverages($reactionsbychar)};
   my @worstchars = sort {$avgreactionsbychar{$b} <=> $avgreactionsbychar{$a}} (keys %avgreactionsbychar);

   my $worstcharsreport = '';

   if (@worstchars) {
      my $worstcount = 0;

      foreach my $ch (@worstchars) {
         $worstcharsreport .= sprintf ("\t%s\t%i ms\n", $ch, $avgreactionsbychar{$ch} * 1000 + 0.5);
         $autoextraweights .= $ch; # practice slowest chars more in future 
         last if ($worstcount++ > 4);
      }
   }

   $rwdf->{controls}->{worstchars}->Contents($worstcharsreport);

   # Report average reaction times by position in word
   my %avgreactionsbypos = %{gethistogramaverages($reactionsbypos)};
   my @worstcharpos = sort keys %avgreactionsbypos;

   my $worstcharposreport = '';

   if ($e->{measurecharreactions}) {
      if (@worstcharpos) {
         foreach my $pos (@worstcharpos) {
            $worstcharposreport .= sprintf ("\t%s\t%i ms\n", $pos, $avgreactionsbypos{$pos} * 1000 + 0.5);
         }
      }
   } else {
      my $wordspacetime = 4 * (1 + int($e->{extrawordspaces})) * $pulsetime;
      # show reactions from earliest opportunity to detect end of word, not from end of gap
      $worstcharposreport .= sprintf("Word start\t%i ms\n", ($avgreactionsbypos{-2} + $wordspacetime) * 1000 + 0.5);
      $worstcharposreport .= sprintf("Word end  \t%i ms\n", ($avgreactionsbypos{-1} + $wordspacetime) * 1000 + 0.5);
      $worstcharposreport .= sprintf("Space time\t%i ms\n", $wordspacetime * 1000 + 0.5);
   }

   $rwdf->{controls}->{worstcharpos}->Contents($worstcharposreport);

   # Report success rate by position in word
   my %avgsuccessbypos = %{gethistogramaverages($successbypos)};

   my $positionsuccessreport = '';

   foreach my $pos (sort keys %avgsuccessbypos) {
      my $avgsuccessbypospc = int($avgsuccessbypos{$pos} * 100 + 0.5);
      $positionsuccessreport .= sprintf("\t%i\t%i%% (%i / %i)\n", $pos, $avgsuccessbypospc, $successbypos->{total}->{$pos}, $successbypos->{count}->{$pos});
   }

   $rwdf->{controls}->{positionsuccesses}->Contents($positionsuccessreport); 
}

sub autoweight {
   my $xweights = $autoextraweights; 
   $xweights =~ s/[ _]//g; # blanks are valid characters but should not be picked
   $e->{xweights} = $xweights;
   setdictsizes();
}

sub setControlState {
   my $state = shift;

   foreach my $k (keys(%{$e})) {
      if (($mwdf->{attr}->{$k} =~ /entry|checkbutton/) and not($mwdf->{attr}->{$k} =~ /locked/)) {
         $mwdf->{controls}->{$k}->configure(-state=>$state);
      }
   }

   $mwdf->{controls}->{start}->configure(-state=>$state);
}

sub syncflush {
   # Check that previous playing has finished so timings are accurate
   my $pollctr;

   for ($pollctr = 0; $pollctr < 50; $pollctr++) {
      last if (-f $mp2readyfile);
      usleep(20000); # microseconds
   }

   unlink($mp2readyfile) if -f $mp2readyfile;
}

sub setdictsizes {
   return; ## now done by TestWordGenerator module
}

sub populateresultswindow {
   my $rwdf = shift;

   $rwdf->addEntryField('Duration', 'duration', 30, undef, undef, undef, '');
   $rwdf->addEntryField('Word success rate', 'wordreport', 30, undef, undef, undef, '');
   $rwdf->addEntryField('Character success rate', 'charreport', 30, undef, undef, undef, '');
   $rwdf->addEntryField('Missed characters', 'missedchars', 30, undef, undef, undef, '');
   $rwdf->addEntryField('Mistaken characters', 'mistakenchars', 30, undef, undef, undef, '');
   $rwdf->addEntryField('Achieved paris wpm', 'pariswpm', 30, undef, undef, undef, '');
   $rwdf->addEntryField('Achieved character wpm', 'charswpm', 30, undef, undef, undef, '');
   $rwdf->addEntryField('Relative character weight', 'relcharweight', 30, undef, undef, undef, '');
   $rwdf->addEntryField('Inter-character pause factor', 'charpausefactor', 30, undef, undef, undef, '');

   $rwdf->addWideTextField('Slowest reactions by character:', 'worstchars', 5, 35, '', undef, undef, '');
   $rwdf->addWideTextField('Reactions by position:', 'worstcharpos', 10, 35, '', undef, undef, '');
   $rwdf->addWideTextField('Success rate by position:', 'positionsuccesses', 10, 35, '', undef, undef, '');

   $rwdf->addButtonField('OK', 'ok',  undef, sub{$rwdf->{w}->destroy}, '');
}

