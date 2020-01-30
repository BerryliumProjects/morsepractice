#! /usr/bin/perl 
use strict;
use warnings;

use Tk;
use Tk::ROText;
use Tk::DialogBox;

use Data::Dumper;
use Tk::After;
use IO::Handle;
use Time::HiRes qw(time usleep);

use charcodes; # definitions of characters as dit-dah sequences
our %charcodes;

use dialogfields;
use testwordgenerator;
use histogram;
use maindialog;

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

my $pulsetime;
my $extracharpausetime;
my $slowresponsethreshold = 1; # seconds
my $defaultreaction = 0.5; # seconds - used if realignment results in < minimum
my $minimumreaction = 0.25; # seconds - below this is suspicious unless character is correct

my @alluserinput = ();
my $userwordcnt;
my $testwordcnt;
my @userwordinput;
my @testwordstats;

my @subdictionary;

# container for histograms
my $h = {};

my $weightedkeylist; # can include repeats of common characters

my $knownchars = join('', sort keys(%charcodes));
$knownchars =~ s/ //; # remove blank as an option

my $mdlg = MainDialog->init(\&mainwindowcallback, $knownchars);
my $e = $mdlg->{e};
my $d = $mdlg->{d};

validateSettings();
setexweights();
$mdlg->setControlState('normal');
$mdlg->show;
exit 0;

sub mainwindowcallback {
   my $id = shift; # name of control firing event

   if ($id eq 'exercisekey') {
      my $ch = shift;
      checkchar($ch);
   } elsif ($id eq 'setexweights') {
      setexweights();
   } elsif ($id eq 'calibrate') {
      calibrate();
   } elsif ($id eq 'autoweight') {
      autoweight();
   } elsif ($id eq 'generate') {
      validateSettings();
      $d->Contents(generateText());
   } elsif ($id eq 'play') {
      playText($d->Contents);
   } elsif ($id eq 'start') {
      startAuto();
   } elsif ($id eq 'finish') {
      abortAuto();
   }
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
   # using standard average word length 5, 6 extra pauses per (word + space)
   $extracharpausetime = 60 / 6 * (1 / $e->{effwpm} - 1 / $e->{wpm});
   $weightedkeylist = $e->{keylist} . $e->{xweights};
   $autoextraweights = ''; 

   if (not $e->{minwordlength}) { # check if numeric and > 0
      $e->{minwordlength} = 1;
   }

   if ((not $e->{maxwordlength}) or ($e->{maxwordlength} < $e->{minwordlength})) {
      $e->{maxwordlength} = $e->{minwordlength};
   }

   $twg = TestWordGenerator->new($e->{minwordlength}, $e->{maxwordlength}, $e->{repeatcnt});

   # build selected word list considering complexity and min/max word length
   @subdictionary = ();

   if ($e->{retrymistakes}) {
      $e->{syncafterword} = 1; # 'can't retry unless syncing after each word
   }

   unless ($e->{useqdict} or $e->{useqphrases} or $e->{useedict} or $e->{userandom} or $e->{usescalls} or $e->{useicalls}) {
      $e->{usepseudo} = 1; # ensure at least some words added
   }

   if ($e->{userandom}) {
      $twg->addRandom($weightedkeylist, 200);
   }

   if ($e->{usepseudo}) {
      $twg->addPseudo(200);
   }

   if ($e->{useqdict}) {
      $twg->addDictionary('qsowordlist.txt', $e->{dictoffset}, $e->{dictsize});
      $e->{userelfreq} = 0; # incompatible with using dictionary
   }

   if ($e->{useqphrases}) {
      $twg->addDictionary('qsophrases.txt', $e->{dictoffset}, $e->{dictsize});
      $e->{userelfreq} = 0; # incompatible with using dictionary
   }

   if ($e->{useedict}) {
      $twg->addDictionary('wordlist.txt', $e->{dictoffset}, $e->{dictsize});
      $e->{userelfreq} = 0; # incompatible with using dictionary
   }

   if ($e->{usescalls}) {
      $twg->addCallsign(0, 200);
   }

   if ($e->{useicalls}) {
      $twg->addCallsign(1, 50);
   }

   $e->{wordlistsize} = $twg->{size};
}


   
sub startAuto {
   validateSettings();

   open(MP, "|  perl $morseplayer " . join(' ', $e->{wpm}, $e->{effwpm}, $e->{pitch}, $e->{playratefactor}, $e->{dashweight}, $e->{extrawordspaces})) or die; 
   autoflush MP, 1;

   $d->Contents('');
   $d->focus;
   $mdlg->setControlState('disabled');
   $successes = 0;
   $pulsecount = 0;
   $totalcharcount = 0;
   $nonblankcharcount = 0;
   $abortpendingtime = 0;
   $prevspacetime = 0;
   @alluserinput = ();
   @userwordinput = ();
   $userwordcnt = 0;
   $testwordcnt = 0;
   $userword = '';

   $h->{reactionsbychar} = Histogram->new;
   $h->{reactionsbypos} = Histogram->new;
   $h->{missedchars} = Histogram->new;
   $h->{mistakenchars} = Histogram->new;
   $h->{successbypos} = Histogram->new;
 
   print MP "= \n";
   sleep 2;
   syncflush();
   unlink($mp2statsfile);

   $starttime = undef;
 
   $mdlg->startusertextinput;

   if ($e->{syncafterword}) {   
      print MP $twg->chooseWord . "\n";
   } else {
      my $testtext = generateText();
      my @testtext = split(/ /, $testtext);     
      $testwordcnt = scalar(@testtext); # target word count
      print MP "$testtext\n";
   }
}

sub abortAuto {
   $abortpendingtime = time();
   $userabort = 1;
   $starttime = time() unless defined $starttime; # ensure defined
   $duration = time() - $starttime;
   stopAuto(); 
}

sub checkchar {
   my $ch = shift;

   $starttime = time() unless defined $starttime; # count from first response
   $duration = time() - $starttime;

   $ch = '' unless defined($ch);
   $ch = lc($ch);
   $ch =~ s/\r/ /; # newline should behave like space as word terminator

   if ($ch ne '') { # ignore empty characters (e.g. pressing shift)
      if ($e->{maxwordlength} > 1) {
         checkwordchar($ch);
      } else {
         checksinglechar($ch);
      }
   }

   if ($abortpendingtime) {
      stopAuto();
   }
}

sub checkwordchar {
   my $ch = shift;
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
         chomp(@userwordinput);
         push(@alluserinput, @userwordinput);
         @userwordinput = ();

         if ($e->{syncafterword}) { 
            syncflush();

            $testwordcnt++; # length of test is variable depending on progress in test duration

            if ($e->{practicetime} > 0 and ($e->{practicetime} * 60) < $duration) {
               $abortpendingtime = time(); 
            } else {
               my $testword = $twg->{prevword};
               if (($userword ne $testword) and $e->{retrymistakes}) {
                  $d->insert('end', '# ');
               } else {
                  $testword = $twg->chooseWord;
               }

               print MP "$testword\n";
            }
         } else {
            $userwordcnt++;

            if ($userwordcnt >= $testwordcnt) {
               $abortpendingtime = time();
            } 
         }

         $userword = '';
      } else {
         push(@userwordinput, "$ch\t$thischtime\n");
         $userword .= $ch;
      }
   }
}

sub checksinglechar {
   my $ch = shift;

   my $thischtime = time();

   if ($ch ne ' ' and $ch ne "\b") {
      push(@userwordinput, "$ch\t$thischtime");
      push(@userwordinput, " \t$thischtime");
      push(@alluserinput, @userwordinput);
      @userwordinput = ();

      syncflush();

      $testwordcnt++; # length of test is variable depending on progress in test duration

      if ($e->{practicetime} > 0 and ($e->{practicetime} * 60) < $duration) {
         $abortpendingtime = time(); 
      } else {
         my $testword = $twg->{prevword};

         if (("$ch" ne $testword) and $e->{retrymistakes}) {
            $d->insert('end', '# '); # repeat previous word
         } else {
            $testword = $twg->chooseWord;
         }

         print MP "$testword\n";
      }
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
         splice @$userinputref, $difpos, 0, {ch => '_', t => $userinputref->[$difpos]->{t}};
      }
   }
}

sub getwordtext {
   my $wordref = shift;

   my $wordlen = scalar(@$wordref) - 1; # ignore trailing space
   my $wordtext = '';

   for (my $i = 0; $i < $wordlen; $i++) {
      $wordtext .= $wordref->[$i]->{ch};
   }

   return $wordtext;
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

      if ($testchar eq ' ') {
         # measure reaction from when next character would have been expected
         $endchartime = $teststatsref->[$i-1]->{t};
      }

      my $testcharduration = $testpulsecnt * $pulsetime;
      my $usertime = $userinput->{t};

      if (not defined $usertime) {
         # user input missing - possible at end of exercise after all other re-alignments attempted
         # use reasonable dummy values
         $usertime = $endchartime;
         $userchar = '_';
      }

      my $reaction = $usertime - $endchartime;

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
            $h->{missedchars}->add($testchar, 1);

	    # increase frequency of confused characters for later
            # any invalid characters will be played as = 
	    $autoextraweights .= $testchar . $testchar;
            $h->{successbypos}->add($i, 0);
         } elsif ($userchar ne $testchar) {
            $h->{mistakenchars}->add($testchar, 1);	    

	    # increase frequency of confused characters for later
            # any invalid characters will be played as = 
	    $autoextraweights .= $userchar . $testchar . $testchar;
            $h->{successbypos}->add($i, 0);
         } else { 
            $h->{successbypos}->add($i, 1); 
         }

         if ($e->{measurecharreactions}) {
            if ($reaction > $slowresponsethreshold) {
               $autoextraweights .= $testchar;
            }
         }
      }

      my $typingtimems = '';
      my $reactionms = '';

      if ($userchar ne '_') {
         $reactionms = int($reaction * 1000 + 0.5);

         if ($reactionms <= 0) {
            $reactionms = ''; # don't show misleading results
         }

         if (defined $prevusertime) {
            $typingtimems = int(($usertime - $prevusertime) * 1000);

            if ($typingtimems <= 0) {
               $typingtimems = '' # don't show misleading values
            }
         }

         $prevusertime = $usertime;
      }

      my $testchardurationms = int($testcharduration * 1000 + 0.5);
      # treat reactionms and typingtimems as strings as could be blank if n/a
      printf "%1s%5d%2s%5s%5s\n", $testchar, $testchardurationms, $userchar, $reactionms, $typingtimems;

      if ($reaction < $minimumreaction and $userchar eq '_') {
         $reaction = $defaultreaction;  # avoid suspicious reactions from skewing stats
      }

      my $histcharindex = ($testchar eq ' ') ? '>' : $testchar; # for legibility
      my $histposindex = ($testchar eq ' ') ? -1 : $i; # notional index for word gap

      if ($e->{measurecharreactions}) {
         $h->{reactionsbychar}->add($histcharindex, $reaction);
      }

      # also record reaction/histogram by position in word (key:tab-n)
      if ($e->{measurecharreactions} or $histposindex < 0) {
         $h->{reactionsbypos}->add($histposindex, $reaction);
      }
   }

   # if in word recognition mode, note reaction time to start entering word
   # the end of the word can be detected as soon as the next expected element is absent
   if (not $e->{measurecharreactions}) {
      my $wordreaction = $startuserwordtime - $endtestwordtime;

      if ($wordreaction > -3 and $wordreaction < 3) { # ignore if either time is missing
         $h->{reactionsbypos}->add(-2, $wordreaction);

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

   # read test and user word structures from formatted records
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

   # re-align words in case user missed a space and combined two words
   my $iuw = 0;

   for (my $itw = 0; $itw < scalar(@testwords); $itw++) {
      my $extrauserword = splitword($userwords[$iuw], $testwords[$itw]);
      $iuw++;

      if (scalar($extrauserword)) {
         # insert extra word after the current one. The original userword will have been shortened
         splice(@userwords, $iuw, 0, $extrauserword);
      }
   }

   # re-align words in case user missed a whole word but then successfully resynced
   my $previoususerwordtext = '';

   for (my $iw = 0; $iw < scalar(@testwords); $iw++) {
      # get text of words
      my $userwordtext = getwordtext($userwords[$iw]);
      my $testwordtext = getwordtext($testwords[$iw]);

      if (($testwordtext ne $userwordtext) and ($testwordtext eq $previoususerwordtext)) {
         # insert notional empty user word with the same time as the start of the next user word

         my $dummyspacetime = $userwords[$iw]->[0]->{t};
         my $dummyspacerec = {ch => ' ', t => $dummyspacetime};
         my $dummyword = [$dummyspacerec]; # reference to an array containing one element

         splice(@userwords, $iw - 1, 0, $dummyword);
         $userwordtext = $previoususerwordtext;
      }

      $previoususerwordtext = $userwordtext;
   }

   for (my $iw = 0; $iw < scalar(@testwords); $iw++) {
      # re-align characters in words in case some missed
      alignchars($userwords[$iw], $testwords[$iw]);

      # analyse word characters
      markword($userwords[$iw], $testwords[$iw]);
   }
}

sub splitword {
   my $userinputref = shift;
   my $teststatsref = shift;

   my $userlen = scalar(@$userinputref);
   my $testlen = scalar(@$teststatsref);
   my @userinput2;

   if ($userlen > $testlen + 1) {
      @userinput2 = splice(@$userinputref, $testlen - 1); # split the word to match the length of the target excluding its final space
      my $extrauserspacetime = $userinput2[0]->{t}; # the notional time at which the extra space is deemed to have been entered
      push(@$userinputref, {ch=>' ', t=>$extrauserspacetime}); # re-terminate first word
   }

   if (@userinput2) {
      return \@userinput2;
   } # else implicitly return undef
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
      $text .= $twg->chooseWord . ' ';
   }

#  chop($text); # remove final blank 
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

sub stopAuto {
   $mdlg->stopusertextinput;

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
   }

   my $text = $d->Contents;

   # remove incorrect attempts after marking text
   $text =~ s/[^\[\]\#\s]+ \# //g;

   # sanitise remaining formatting characters used when marking test
   $text =~ s/[\[\]\#\_]//g;
   # collapse whitespace sequences to a single space
   $text =~ s/\s+/ /g;

   # enable test to be played
   $d->Contents($text);
   $mdlg->setControlState('normal');

   if ($e->{dictsize} == 0) {
      $e->{dictsize} = 9999; # avoid lock ups 
   }

   unlink($mp2readyfile) if -f $mp2readyfile;
}

sub showresults {
   my $rw = $mdlg->{w}->DialogBox(-title=>'Results', -buttons=>['OK']); # results window
   my $rwdf = DialogFields->init($rw);
   populateresultswindow($rwdf);

   # statistics used: 
   #   words:  testwordcnt, successes
   #   chars:  nonblankcharcount, totalcharcount, mistakenchars, missedchars
   #   pulses: pulsecount
   #   reactions: reactionsbychar, reactionsbypos - reactions recorded for bad chars but not missed chars

   my $successrate = ($testwordcnt ? $successes / $testwordcnt : 0);
   my $missedcharcnt = $h->{missedchars}->grandcount;
   my $mistakencharcnt = $h->{mistakenchars}->grandcount;
   my $charsuccessrate = ($nonblankcharcount ? 1 - ($missedcharcnt + $mistakencharcnt) / $nonblankcharcount : 0);
   my $avgpulsecnt = ($totalcharcount ? $pulsecount / $totalcharcount : 0);

   my $re = $rwdf->entries; # gridframe control values
   $re->{duration} = sprintf('%i', $duration);
   $re->{wordreport} = sprintf('%i%% (%i / %i)', $successrate * 100, $successes, $testwordcnt);
   $re->{charreport} = sprintf('%i%% (%i missed, %i wrong / %i)', $charsuccessrate * 100, $missedcharcnt, $mistakencharcnt, $nonblankcharcount);
   $re->{missedchars} = join('', @{$h->{missedchars}->keys});
   $re->{mistakenchars} = join('', @{$h->{mistakenchars}->keys});
   $re->{pariswpm} = sprintf('%.1f', ($pulsecount / 50) * $charsuccessrate / ($duration / 60)); # based on elements decoded
   $re->{charswpm} = sprintf('%.1f', ($e->{effwpm} * $charsuccessrate)); # based on characters decoded
   $re->{relcharweight} = sprintf('%i%%', $avgpulsecnt / (50 / 6) * 100); # as percentage
   $re->{charpausefactor} = sprintf('%i%%', $extracharpausetime / $pulsetime / 2 * 100); # as percentage
 
 
   # Report slowest average reaction times by character
   my %avgreactionsbychar = %{$h->{reactionsbychar}->averages};
   my @worstchars = sort {$avgreactionsbychar{$b} <=> $avgreactionsbychar{$a}} (keys %avgreactionsbychar);

   my $worstcharsreport = '';

   if (@worstchars) {
      my $worstcount = 0;

      foreach my $ch (@worstchars) {
         $worstcharsreport .= sprintf ("\t%s\t%i ms\n", $ch, $avgreactionsbychar{$ch} * 1000 + 0.5);
         last if ($worstcount++ > 4);
      }
   }

   $rwdf->{controls}->{worstchars}->Contents($worstcharsreport);

   # Report average reaction times by position in word
   my %avgreactionsbypos = %{$h->{reactionsbypos}->averages};
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
      # reactions are from earliest opportunity to detect end of word, not from end of gap if extra spaces have been inserted
      $worstcharposreport .= sprintf("Word start\t%i ms\n", $avgreactionsbypos{-2} * 1000 + 0.5);
      $worstcharposreport .= sprintf("Word end  \t%i ms\n", $avgreactionsbypos{-1} * 1000 + 0.5);
      $worstcharposreport .= sprintf("Space time\t%i ms\n", $wordspacetime * 1000 + 0.5);
   }

   $rwdf->{controls}->{worstcharpos}->Contents($worstcharposreport);

   # Report success rate by position in word
   my %avgsuccessbypos = %{$h->{successbypos}->averages};

   my $positionsuccessreport = '';

   foreach my $pos (sort keys %avgsuccessbypos) {
      my $avgsuccessbypospc = int($avgsuccessbypos{$pos} * 100 + 0.5);
      $positionsuccessreport .= sprintf("\t%i\t%i%% (%i / %i)\n", $pos, $avgsuccessbypospc, $h->{successbypos}->keytotal($pos), $h->{successbypos}->keycount($pos));
   }

   $rwdf->{controls}->{positionsuccesses}->Contents($positionsuccessreport); 
   $rw->Show;
}

sub autoweight {
   my $xweights = $autoextraweights; 
   $xweights =~ s/[ _]//g; # blanks are valid characters but should not be picked
   $e->{xweights} = $xweights;
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

#    $rwdf->addButtonField('OK', 'ok',  undef, sub{$rwdf->{w}->destroy}, '');
}

