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
use word;

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
   Word->debounce('');
   @userwords = ();
   $userwordinput = Word->createfromchar;
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
      if ($e->{maxwordlength} == 1 and $e->{syncafterword}) {
         checksinglechar($ch);
      } else {
         checkwordchar($ch);
      }
   }

   if ($abortpendingtime) {
      stopAuto();
   }
}

sub checkwordchar {
   my $ch = shift;

   if ($ch eq "\b") {
      if ($e->{allowbackspace}) {
         # discard final character and stats 
         $userwordinput->undo;
      }
   } else {
      $userwordinput->append($ch);

      if ($userwordinput->{complete}) {
         if ($e->{syncafterword}) { 
            syncflush();

            if (($e->{practicetime} * 60) < (time() - $starttime)) {
               $abortpendingtime = time(); 
            } else {
               my $testword = $twg->{prevword};
               my $userword = $userwordinput->wordtext;

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
         $userwordinput = Word->createfromchar;
      }
   }
}

sub checksinglechar {
   my $ch = shift;

   my $userwordinput = Word->createfromchar($ch);

   push(@userwords, $userwordinput);
   syncflush();

   if ($e->{practicetime} * 60 < time() - $starttime) {
      $abortpendingtime = time(); 
   } else {
      my $testword = $twg->{prevword};

      if (($userwordinput->wordtext ne $testword) and $e->{retrymistakes}) {
         $d->insert('end', '# '); # repeat previous word
      } else {
         $testword = $twg->chooseWord;
      }

      print MP "$testword\n";
   }
}

sub addtestweight {
   # add extra weight to poorly received characters, for the next practice session
   my $userchar = shift;
   my $testchar = shift;
   my $slowreaction = shift;

   if ($testchar ne ' ') {
      if ($userchar eq '_') {
         # increase frequency of missed characters for later
         $autoextraweights .= $testchar . $testchar;
      } elsif ($userchar ne $testchar) {
         # increase frequency of confused characters for later
         # any invalid characters will be played as = 
         $autoextraweights .= $userchar . $testchar . $testchar;

         if ($slowreaction) {
            $autoextraweights .= $testchar;
         }
      }
   }
}

my $prevusertime = undef; # used by showcharstats

sub showcharstats {
   # show character statistics on the terminal
   my $userchar = shift;
   my $testchar = shift;
   my $reaction = shift;
   my $usertime = shift;
   my $testpulsecnt = shift;

   my $typingtimems = '';
   my $reactionms = '';

   if ($userchar ne '') {
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
      }

      my $testchardurationms = int($testpulsecnt * 1.2 / $e->{wpm} * 1000 + 0.5);
      # treat reactionms and typingtimems as strings as could be blank if n/a
      printf "%1s%5s%2s%5s%5s\n", $testchar, $testchardurationms, $userchar, $reactionms, $typingtimems;

      if ($testchar eq ' ') {
         $prevusertime = undef; # prime for next word
      } else {
         $prevusertime = $usertime;
      }
   } else { 
      $reactionms = int($reaction * 1000 + 0.5);
      printf "Word:%4s\n", $reactionms;
   }
}

sub markchar { 
   # find characters in error and mark reactions
   my $userchar = shift;
   my $usertime = shift;
   my $testchar = shift;
   my $endchartime = shift;
   my $testpulsecnt = shift;
   my $i = shift;
   my $r = shift;

   my $reaction = $usertime - $endchartime;

   addtestweight($userchar, $testchar, $reaction > $slowresponsethreshold);

   showcharstats($userchar, $testchar, $reaction, $usertime, $testpulsecnt);

   $r->{pulsecount} += $testpulsecnt; # for whole session
   $r->{nonblankcharcount}++;
 
   if ($userchar eq '_') { # missed char
      $r->{missedchars}->add($testchar, 1);
      $r->{successbypos}->add($i, 0);
   } elsif ($userchar ne $testchar) {
      $r->{mistakenchars}->add($testchar, 1);
      $r->{successbypos}->add($i, 0);
   } else { 
      $r->{successbypos}->add($i, 1);
   }

   if ($reaction < $minimumreaction and $userchar eq '_') {
      $reaction = $defaultreaction;  # avoid suspicious reactions from skewing stats
   }

   my $histcharindex = $testchar;
   my $histposindex = $i;

   if ($e->{measurecharreactions}) {
      $r->{reactionsbychar}->add($testchar, $reaction);
      $r->{reactionsbypos}->add($i, $reaction);
   }
}

sub markword { 
   # find characters in error and mark reactions
   my $userinputref = shift;
   my $teststatsref = shift;
   my $r = shift;

   my $markuserword = $userinputref->wordtext;
   my $marktestword = $teststatsref->wordtext;
 
   my $testwordlength = length($marktestword);
   for (my $i = 0; $i < $testwordlength; $i++) {
      my ($userchar, $usertime) = $userinputref->chardata($i);
      my ($testchar, $endchartime, $testpulsecnt) = $teststatsref->chardata($i);
      markchar($userchar, $usertime, $testchar, $endchartime, $testpulsecnt, $i, $r);
   }

   my ($userspace, $userspacetime) = $userinputref->chardata($testwordlength);
   my ($testspace, $endspacetime, $testspacepulsecnt) = $teststatsref->chardata($testwordlength);

   # measure reaction from when next character would have been expected
   $endspacetime = $teststatsref->{endtime};

   my $spacereaction = $userspacetime - $endspacetime;
   showcharstats(' ', ' ', $spacereaction, $userspacetime, $testspacepulsecnt);

   $r->{pulsecount} += $testspacepulsecnt; # for whole session

   if ($e->{measurecharreactions}) {
      $r->{reactionsbychar}->add('>', $spacereaction);
   }

   # also record reaction/histogram by position in word (key:tab-n)
   $r->{reactionsbypos}->add(-1, $spacereaction);

   # if in word recognition mode, note reaction time to start entering word
   # the end of the word can be detected as soon as the next expected element is absent
   if (not $e->{measurecharreactions}) {
      my $wordreaction = $userinputref->{starttime} - $teststatsref->{endtime};
      $r->{reactionsbypos}->add(-2, $wordreaction);
      showcharstats('', '', $wordreaction);
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
   my $statshandle;
   open ($statshandle, $mp2statsfile);

   my @testwords = ();
   my $testword = Word->createfromfile($statshandle);

   # read test and user word structures from formatted records
   while ($testword->{complete}) {
      # if exercise was terminated early, ignore any test content after that time
      # allow up to a second of user anticipation on last word
      if ($abortpendingtime > 0 and $testword->{endtime} > $abortpendingtime + 1) {
         last;
      }

      push(@testwords, $testword);
      $testword = Word->createfromfile($statshandle);
   }

   close($statshandle);
   unlink($mp2statsfile);

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

   for (my $itw = 0; $itw < scalar(@testwords); $itw++) {
      last unless defined $userwords[$iuw];

      my (@newwords) = $userwords[$iuw]->split($testwords[$itw]->wordtext);
      my $newcnt = scalar(@newwords);

      if ($newcnt == 2) {
         # replace original word with two new ones
          splice(@userwords, $iuw, 1, @newwords);
      }

      $iuw += $newcnt;
   }

   # re-align words in case user missed a whole word but then successfully resynced
   my $previoususerwordtext = '';

   for (my $iw = 0; $iw < $r->{testwordcnt}; $iw++) {
      last unless defined $userwords[$iw];

      my $userwordtext = $userwords[$iw]->wordtext;
      my $testwordtext = $testwords[$iw]->wordtext;

      if (($userwordtext ne '') and ($testwordtext ne $userwordtext) and ($testwordtext eq $previoususerwordtext)) {
         # insert notional empty user word with the same time as the start of the next user word

         my $dummyword = Word->createwordfromchar('');
         my $dummyspacetime = $userwords[$iw]->{starttime};
         $dummyword->append(' ', $dummyspacetime);

         splice(@userwords, $iw - 1, 0, $dummyword);
         $userwordtext = $previoususerwordtext;
      }

      $previoususerwordtext = $userwordtext;
   }

   # there might still be less words entered by user than expected. To avoid skewing statistics, don't mark any missed at the end

   for (my $iw = 0; $iw < $r->{testwordcnt}; $iw++) {
      last unless defined $userwords[$iw];

      # re-align characters in words in case some missed
      $userwords[$iw]->align($testwords[$iw]->wordtext);

      # analyse word characters
      markword($userwords[$iw], $testwords[$iw], $r);
   }

   return $r;
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

