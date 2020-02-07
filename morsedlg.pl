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
use resultsdialog;

# constants
my $slowresponsethreshold = 1; # seconds
my $defaultreaction = 0.5; # seconds - used if realignment results in < minimum
my $minimumreaction = 0.25; # seconds - below this is suspicious unless character is correct
my $mp2readyfile = '/var/tmp/mp2ready.txt';
my $mp2pidfile = '/var/tmp/mp2pid.txt';
my $mp2statsfile = '/var/tmp/mp2stats.txt';
my $morseplayer = "./morseplayer2.pl"; 

# global variables
my $twg;
my $starttime;
my $autoextraweights = '';
my $abortpendingtime;
my $userabort;
my $prevspacetime;
my @userwords;
my $testwordcnt;
my $userwordinput;

my $mdlg = MainDialog->init(\&mainwindowcallback);
my $e = $mdlg->{e};
my $d = $mdlg->{d};

unlink($mp2pidfile) if -f $mp2pidfile;
validateSettings();
setexweights();

$e->{keylist} = join('', sort keys(%charcodes));
$e->{keylist} =~ s/ //; # remove blank as an option

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
      prepareTest();
      $d->Contents(generateText());
   } elsif ($id eq 'play') {
      playText($d->Contents);
   } elsif ($id eq 'flash') {
      flashText($d->Contents);
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

sub prepareTest {
   $autoextraweights = ''; 

   $twg = TestWordGenerator->new($e->{minwordlength}, $e->{maxwordlength}, $e->{repeatcnt});

   # build selected word list considering complexity and min/max word length

   if ($e->{userandom}) {
      $twg->addRandom($e->{keylist} . $e->{xweights}, 200);
   }

   if ($e->{usepseudo}) {
      $twg->addPseudo(200);
   }

   if ($e->{useqdict}) {
      $twg->addDictionary('qsowordlist.txt', $e->{dictoffset}, $e->{dictsize});
   }

   if ($e->{useqphrases}) {
      $twg->addDictionary('qsophrases.txt', $e->{dictoffset}, $e->{dictsize});
   }

   if ($e->{useedict}) {
      $twg->addDictionary('wordlist.txt', $e->{dictoffset}, $e->{dictsize});
   }

   if ($e->{usescalls}) {
      $twg->addCallsign($e->{europrefix}, 0, 200);
   }

   if ($e->{useicalls}) {
      $twg->addCallsign($e->{europrefix}, 1, 50);
   }

   $e->{wordlistsize} = $twg->{size};
}



sub validateSettings {
   if (not $e->{minwordlength}) { # check if numeric and > 0
      $e->{minwordlength} = 1;
   }

   if ((not $e->{maxwordlength}) or ($e->{maxwordlength} < $e->{minwordlength})) {
      $e->{maxwordlength} = $e->{minwordlength};
   }

   if ($e->{retrymistakes}) {
      $e->{syncafterword} = 1; # 'can't retry unless syncing after each word
   }

   unless ($e->{useqdict} or $e->{useqphrases} or $e->{useedict} or $e->{userandom} or $e->{usescalls} or $e->{useicalls}) {
      $e->{usepseudo} = 1; # ensure at least some words added
   }

   unless ($e->{practicetime} =~ /^[\d\.]+$/ and $e->{practicetime} > 0){
      $e->{practicetime} = 2;
   }
}


   
sub startAuto {
   validateSettings();
   prepareTest();

   open(MP, "|  perl $morseplayer " . join(' ', $e->{wpm}, $e->{effwpm}, $e->{pitch}, $e->{playratefactor}, $e->{dashweight}, $e->{extrawordspaces})) or die; 
   autoflush MP, 1;

   $d->Contents('');
   $d->focus;
   $mdlg->setControlState('disabled');
   $abortpendingtime = 0;
   $userabort = 0;
   $prevspacetime = 0;
   @userwords = ();
   $userwordinput = [];
   $testwordcnt = 0;

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
   stopAuto(); 
}

sub checkchar {
   my $ch = shift;

   $starttime = time() unless defined $starttime; # count from first response

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
      if ($e->{allowbackspace}) {
         # discard final character and stats 
         pop(@{$userwordinput});
      }
   } else {
      if ($ch eq ' ') {
         # ignore a double space if less than 500ms between them

         if ((scalar(@{$userwordinput}) == 0) and ($thischtime < $prevspacetime + 0.5)) {
            $ch = '';
         } else {
            push(@{$userwordinput}, {ch => ' ', t => $thischtime});
         }

         $prevspacetime = $thischtime;

         if ($e->{syncafterword}) { 
            syncflush();

            if (($e->{practicetime} * 60) < (time() - $starttime)) {
               $abortpendingtime = time(); 
            } else {
               my $testword = $twg->{prevword};
               my $userword = getwordtext($userwordinput);

               if (($userword ne $testword) and $e->{retrymistakes}) {
                  $d->insert('end', '# ');
               } else {
                  $testword = $twg->chooseWord;
               }

               print MP "$testword\n";
            }
         } else {
            if (scalar(@userwords) + 1 >= $testwordcnt) {
               $abortpendingtime = time();
            } 
         }

         push(@userwords, $userwordinput);
         $userwordinput = [];
      } else {
         push(@{$userwordinput}, {ch => $ch, t => $thischtime});
      }
   }
}

sub checksinglechar {
   my $ch = shift;

   my $thischtime = time();

   if ($ch ne ' ' and $ch ne "\b") {
      push(@{$userwordinput}, {ch => $ch, t => $thischtime});
      push(@{$userwordinput}, {ch => ' ', t => $thischtime});
      push(@userwords, $userwordinput);
      $userwordinput = [];

      syncflush();

      if ($e->{practicetime} * 60 < time() - $starttime) {
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

   return unless (defined $userinputref);

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

   return '' unless (defined $wordref);
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
   my $r = shift;

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

      my $usertime = $userinput->{t};

      if (not defined $usertime) {
         # user input missing - possible at end of exercise after all other re-alignments attempted
         # use reasonable dummy values
         $usertime = $endchartime;
         $userchar = '_';
      }

      my $reaction = $usertime - $endchartime;

      $r->{pulsecount} += $testpulsecnt; # for whole session

      if (not $e->{measurecharreactions}) {
         # note when user started to respond and when end of word was detectable
         $startuserwordtime = $usertime unless $startuserwordtime;
         $endtestwordtime = $endchartime;
      }

      $markuserword .= $userchar unless $userchar eq ' ';
      $marktestword .= $testchar unless $testchar eq ' ';

      if ($testchar ne ' ') {
         $r->{nonblankcharcount}++;
 
         if ($userchar eq '_') { # missed char
            $r->{missedchars}->add($testchar, 1);

            # increase frequency of confused characters for later
            # any invalid characters will be played as = 
            $autoextraweights .= $testchar . $testchar;
            $r->{successbypos}->add($i, 0);
         } elsif ($userchar ne $testchar) {
            $r->{mistakenchars}->add($testchar, 1);

            # increase frequency of confused characters for later
            # any invalid characters will be played as = 
            $autoextraweights .= $userchar . $testchar . $testchar;
            $r->{successbypos}->add($i, 0);
         } else { 
            $r->{successbypos}->add($i, 1);
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

      my $testchardurationms = int($testpulsecnt * 1.2 / $e->{wpm} * 1000 + 0.5);
      # treat reactionms and typingtimems as strings as could be blank if n/a
      printf "%1s%5d%2s%5s%5s\n", $testchar, $testchardurationms, $userchar, $reactionms, $typingtimems;

      if ($reaction < $minimumreaction and $userchar eq '_') {
         $reaction = $defaultreaction;  # avoid suspicious reactions from skewing stats
      }

      my $histcharindex = ($testchar eq ' ') ? '>' : $testchar; # for legibility
      my $histposindex = ($testchar eq ' ') ? -1 : $i; # notional index for word gap

      if ($e->{measurecharreactions}) {
         $r->{reactionsbychar}->add($histcharindex, $reaction);
      }

      # also record reaction/histogram by position in word (key:tab-n)
      if ($e->{measurecharreactions} or $histposindex < 0) {
         $r->{reactionsbypos}->add($histposindex, $reaction);
      }
   }

   # if in word recognition mode, note reaction time to start entering word
   # the end of the word can be detected as soon as the next expected element is absent
   if (not $e->{measurecharreactions}) {
      my $wordreaction = $startuserwordtime - $endtestwordtime;

      if ($wordreaction > -3 and $wordreaction < 3) { # ignore if either time is missing
         $r->{reactionsbypos}->add(-2, $wordreaction);

         printf "Word:  %i\n",  $wordreaction * 1000 + 0.5;
      }
   }

   if ($markuserword eq $marktestword) {
      $r->{successes}++;
      $d->insert('end', "$marktestword ");
   } else {
      $d->insert('end', "$markuserword # [$marktestword] "); 
   }
}

sub marktest {
   my $r = {}; # results structure

   $d->Contents(''); # clear the text display

   # get test report from player
   open (STATS, $mp2statsfile);
   my @teststats = <STATS>;
   close(STATS);
   unlink($mp2statsfile);

   chomp @teststats;

   my @testwords = ();

   # read test and user word structures from formatted records
   while (scalar(@teststats) > 0) {

      my @testwordstats = ();
      my $testwordendtime = 0;

      while (defined (my $teststatsitem = shift(@teststats))) {
         my ($testchar, $testtime, $testpulsecnt) = split(/\t/, $teststatsitem);
         my $testrec = {ch => $testchar, t => $testtime, pcnt => $testpulsecnt};
         push(@testwordstats, $testrec);

         if ($testchar eq ' ') {
            $testwordendtime = $testtime;
            last;
         }
      }

      # if exercise was terminated early, ignore any test content after that time
      # allow up to a second of user anticipation on last word
      if ($abortpendingtime > 0 and $testwordendtime > $abortpendingtime + 1) {
         last;
      }

      if (scalar(@testwordstats) > 1) { # ignore an empty word or just a space
         push(@testwords, \@testwordstats);
      }
   }

   $r->{testwordcnt} = scalar(@testwords);
   $r->{duration} = time() - $starttime;
   $r->{successes} = 0;
   $r->{pulsecount} = 0;
   $r->{nonblankcharcount} = 0;

   $r->{reactionsbychar} = Histogram->new;
   $r->{reactionsbypos} = Histogram->new;
   $r->{missedchars} = Histogram->new;
   $r->{mistakenchars} = Histogram->new;
   $r->{successbypos} = Histogram->new;

   return if ($r->{testwordcnt} == 0); # possible if aborted early

   # re-align words in case user missed a space and combined two words
   my $iuw = 0;

   for (my $itw = 0; $itw < $r->{testwordcnt}; $itw++) {
      my $extrauserword = splitword($userwords[$iuw], $testwords[$itw]);
      $iuw++;

      if (scalar($extrauserword)) {
         # insert extra word after the current one. The original userword will have been shortened
         splice(@userwords, $iuw, 0, $extrauserword);
      }
   }

   # re-align words in case user missed a whole word but then successfully resynced
   my $previoususerwordtext = '';

   for (my $iw = 0; $iw < $r->{testwordcnt}; $iw++) {
      # get text of words
      my $userwordtext = getwordtext($userwords[$iw]);
      my $testwordtext = getwordtext($testwords[$iw]);

      if (($userwordtext ne '') and ($testwordtext ne $userwordtext) and ($testwordtext eq $previoususerwordtext)) {
         # insert notional empty user word with the same time as the start of the next user word

         my $dummyspacetime = $userwords[$iw]->[0]->{t};
         my $dummyspacerec = {ch => ' ', t => $dummyspacetime};
         my $dummyword = [$dummyspacerec]; # reference to an array containing one element

         splice(@userwords, $iw - 1, 0, $dummyword);
         $userwordtext = $previoususerwordtext;
      }

      $previoususerwordtext = $userwordtext;
   }

   for (my $iw = 0; $iw < $r->{testwordcnt}; $iw++) {
      # re-align characters in words in case some missed
      alignchars($userwords[$iw], $testwords[$iw]);

      # analyse word characters
      markword($userwords[$iw], $testwords[$iw], $r);
   }

   return $r;
}

sub splitword {
   my $userinputref = shift;
   my $teststatsref = shift;

   return unless (defined $userinputref); # in case less user words than test words

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

sub flashText {
   my $ftext = shift;
   my $semichartime = 60.0 / 6 / 2 / $e->{effwpm};

   # temporarily remove line buffering from console, otherwise nothing is seen
   select STDOUT;
   local $| = 1;

   print "Text flashing one visible character at a time:\n";
   sleep 2;

   foreach (split(//, $ftext)) {
      # show character for half time, then blank for half
      print "\r$_\t";
      usleep($semichartime * 1000000); # microseconds
      print "\r \t";
      usleep($semichartime * 1000000); # microseconds
   }

   print "\nEnd of text flashing exercise\n\n";
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
      my $res = marktest();

      if (defined $res and $res->{nonblankcharcount} > 0) {
         ResultsDialog::show($res, $mdlg);
      }
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

