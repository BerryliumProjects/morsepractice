#! /usr/bin/perl 
use strict;
use warnings;
package Exercise;

#use Tk;
#use Tk::ROText;
#use Tk::DialogBox;

use Data::Dumper;
#use Tk::After;
use IO::Handle;
use Time::HiRes qw(time usleep);

use lib '.';

#use dialogfields;
use testwordgenerator;
use histogram;
#use maindialog;
#use exercisedialog;
use resultsdialog;
use word;

# constants
my $defaultreaction = 0.5; # seconds - used if realignment results in < minimum
my $minimumreaction = 0.25; # seconds - below this is suspicious unless character is correct
my $mp2readyfile = '/var/tmp/mp2ready.txt';
my $mp2pidfile = '/var/tmp/mp2pid.txt';
my $mp2statsfile = '/var/tmp/mp2stats.txt';
my $morseplayer = "./morseplayer2.pl"; 

# global variables
unlink($mp2pidfile) if -f $mp2pidfile;
# validateSettings();
# setexweights();

# $e->{keylist} = join('', sort keys(%charcodes));
# $e->{keylist} =~ s/ //; # remove blank as an option

# $mdlg->setControlState('normal');
# $mdlg->show;
# exit 0;

sub init {
   my $class = shift;
   
   my $self = {};
   bless($self, $class);
   $self->{dlg} = shift;
   $self->{twg} = undef;
   $self->{starttime} = 0;
   $self->{abortpendingtime} = 0;
   $self->{userwords} = undef;
   $self->{testwordcnt} = 0;
   $self->{userwordinput} = undef;
   $self->{MP} = undef;
   $self->{running} = undef;
   return $self;
}

sub openPlayer {
   my $self = shift;
   my $textmode = shift;

   my $e = $self->{dlg}->{e};

   die "Opening Player when already connected"  if defined($self->{MP});

   my @audiofields = qw/wpm effwpm pitch playratefactor dashweight extrawordspaces attenuation pitchshift/;
   my $textswitch = $textmode ? '-t' : '';
   my %ehash = %{$e}; # simplifies taking a slice of the values
   my $openargs = join(' ', @ehash{@audiofields}, $textswitch); 
   open($self->{MP}, "|  perl $morseplayer $openargs") or die "Failed to connect to player";

   defined($self->{MP}) or die "Player pipe filehandle not defined";
   autoflush {$self->{MP}} 1;
}  

sub openStandardPlayer {
   my $self = shift;
   my $e = $self->{dlg}->{e};

   die "Opening Player when already connected"  if defined($self->{MP});

   my $openargs = join(' ', 20, 20, 440, $e->{playratefactor}, 3, 0, 10, 0);
   open($self->{MP}, "|  perl $morseplayer $openargs") or die "Failed to connect to player";

   defined($self->{MP}) or die "Player pipe filehandle not defined";
   autoflush {$self->{MP}} 1;
}

sub closePlayer {
   my $self = shift;
   my $force = shift;

   my $e = $self->{dlg}->{e};

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

   my $e = $self->{dlg}->{e};

   die unless defined($self->{MP});

   print {$self->{MP}} "$text\n";
}


sub X_mainwindowcallback {
   my $id = shift; # name of control firing event
my $d; #dummy###
   if ($id eq 'exercisekey') {
      my $ch = shift;
      checkchar($ch);
   } elsif ($id eq 'next') {
      runexercise();
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
      validateSettings();
      prepareTest();
      playText();
   } elsif ($id eq 'flash') {
      validateSettings();
      prepareTest();
      flashText();
   } elsif ($id eq 'start') {
      validateSettings();
      prepareTest();
      startAuto();
   } elsif ($id eq 'finish') {
      abortAuto();
   }
}

sub setexweights {
   my $self = shift;
   my $e = $self->{dlg}->{e};
   return if $e->{running};

   if ($e->{userelfreq}) {
      $e->{xweights} = TestWordGenerator->plainEnglishWeights($e->{keylist}); 
   } else {
      $e->{xweights} = '';
   }
}

sub prepareTest {
   my $self = shift;
   my $e = $self->{dlg}->{e};
   return if $e->{running};

   $e->{autoextraweights} = ''; 

   $self->{twg} = TestWordGenerator->new($e->{minwordlength}, $e->{maxwordlength}, $e->{repeatcnt});

   # build selected word list considering complexity and min/max word length

   if ($e->{userandom}) {
      $self->{twg}->addRandom($e->{keylist} . $e->{xweights}, 200);
   }

   if ($e->{usepseudo}) {
      $self->{twg}->addPseudo(200);
   }

   if ($e->{usephonemes}) {
      $self->{twg}->addPhonemes();
   }

   if ($e->{useqdict}) {
      $self->{twg}->addDictionary('qsowordlist.txt', 0, 999);
   }

   if ($e->{useqphrases}) {
      $self->{twg}->addDictionary('qsophrases.txt', 0, 999);
   }

   if ($e->{usehdict}) {
      $self->{twg}->addDictionary('wordlist100.txt', 0, 999);
   }

   if ($e->{useedict}) {
      $self->{twg}->addDictionary('wordlist-complexity.txt', $e->{dictoffset}, $e->{dictsize});
   }

   if ($e->{usescalls}) {
      $self->{twg}->addCallsign($e->{europrefix}, 0, 200);
   }

   if ($e->{useicalls}) {
      $self->{twg}->addCallsign($e->{europrefix}, 1, 50);
   }

   if ($e->{usespecified}) {
      foreach (split(/\s+/, $self->{dlg}->{d}->Contents)) {
         $self->{twg}->addWord($_);
      }
   }

   if ($self->{twg}->{size} < 1) {
      $self->{twg}->addWord('dummy');
   }

   $e->{wordlistsize} = $self->{twg}->{size};

   
}


sub validateSettings {
   my $self = shift;
   my $e = $self->{dlg}->{e};

   if (not $e->{minwordlength}) { # check if numeric and > 0
      $e->{minwordlength} = 1;
   }

   if ((not $e->{maxwordlength}) or ($e->{maxwordlength} < $e->{minwordlength})) {
      $e->{maxwordlength} = $e->{minwordlength};
   }

   if ($e->{retrymistakes}) {
      $e->{syncafterword} = 1; # 'can't retry unless syncing after each word
   }

   unless ($e->{practicetime} =~ /^[\d\.]+$/ and $e->{practicetime} > 0){
      $e->{practicetime} = 2;
   }

   if ($e->{pitchshift} eq '') {
      $e->{pitchshift} = 0;
   }
}


   
sub startAuto {
   my $self = shift;
   my $e = $self->{dlg}->{e};
   return if $e->{running};
   $e->{running} = 1;

   $self->openPlayer();   
      
   $self->{dlg}->{d}->Contents('');
   $self->{dlg}->{d}->focus;
   $self->{dlg}->setControlState('disabled');
   $self->{abortpendingtime} = 0;
   Word->debounce('');
   $self->{userwords} = [];
   $self->{userwordinput} = Word->new;
   $self->{testwordcount} = 0;

   $self->writePlayer("= ");
   sleep 2;
   $self->syncflush;
   unlink($mp2statsfile);

   $self->{starttime} = undef;
 
   $self->{dlg}->startusertextinput;

   if ($e->{syncafterword}) {   
      $self->writePlayer($self->{twg}->chooseWord);
   } else {
      my $testtext = generateText();
      my @testtext = split(/ /, $testtext);     
      $self->{testwordcount} = scalar(@testtext); # target word count
      $self->writePlayer($testtext);
   }
}

sub abortAuto {
   my $self = shift;
   my $e = $self->{dlg}->{e};
   return unless $e->{running};

   $self->{abortpendingtime} = time();
   $self->{starttime} = time() unless defined $self->{starttime}; # ensure defined
   $self->stopAuto();
}

sub checkchar {
   my $self = shift;
   my $e = $self->{dlg}->{e};

   my $ch = shift;
   return unless $e->{running};

   $self->{starttime} = time() unless defined $self->{starttime}; # count from first response

   $ch = '' unless defined($ch);
   $ch = lc($ch);
   $ch =~ s/\r/ /; # newline should behave like space as word terminator

   if ($ch ne '') { # ignore empty characters (e.g. pressing shift)
      if ($e->{maxwordlength} == 1 and $e->{syncafterword}) {
         $self->checkword(Word->createfromchar($ch));
      } else {
         $self->buildword($ch);
      }
   }

   if ($self->{abortpendingtime}) {
      $self->stopAuto();
   }
}

sub buildword {
   my $self = shift;
   my $e = $self->{dlg}->{e};

   my $ch = shift;
   return unless $e->{running};

   if ($ch eq "\b") {
      if ($e->{allowbackspace}) {
         # discard final character and stats
         $self->{userwordinput}->undo;
      }
   } else {
      $self->{userwordinput}->append($ch);

      if ($self->{userwordinput}->{complete}) {
         $self->checkword($self->{userwordinput});
         $self->{userwordinput} = Word->new;
      }
   }
}

sub checkword {
   my $self = shift;
   my $e = $self->{dlg}->{e};

   $self->{userwordinput} = shift;
   return unless $e->{running};

   if ($e->{syncafterword}) {
      $self->syncflush;

      if (($e->{practicetime} * 60) < (time() - $self->{starttime})) {
         $self->{abortpendingtime} = time();
      } else {
         my $testword = $self->{twg}->{prevword};
         my $userword = $self->{userwordinput}->wordtext;

         if (($userword ne $testword) and $e->{retrymistakes}) {
            $self->{dlg}->{d}->insert('end', '# ');
         } else {
            $testword = $self->{twg}->chooseWord;
         }

         $self->writePlayer($testword);
      }
   } else {
      if (scalar(@{$self->{userwords}}) + 1 >= $self->{testwordcount}) {
         $self->{abortpendingtime} = time();
      }
   }

   push(@{$self->{userwords}}, $self->{userwordinput});
}


sub markword { 
   my $self = shift;
   my $e = $self->{dlg}->{e};

   # find characters in error and mark reactions
   my $userinputref = shift;
   my $teststatsref = shift;
   my $r = shift;

   my $markuserword = $userinputref->wordtext;
   my $marktestword = $teststatsref->wordtext;

   if ($markuserword eq $marktestword) {
      $r->{successes}++;
   }

   my $testwordlength = length($marktestword);
   my $prevtestchar = '';

   for (my $i = 0; $i < $testwordlength; $i++) {
      my ($userchar, $usertime) = $userinputref->chardata($i);
      my ($testchar, $endchartime, $testpulsecnt) = $teststatsref->chardata($i);

      $r->{pulsecount} += $testpulsecnt; # for whole session
      $r->{nonblankcharcount}++;

      if ($userchar eq '_' or $userchar eq '-') { # missed char
         $r->{missedchars}->add($testchar, 1);
         $r->{successbypos}->add($i, 0);
         $r->{focuschars} .= $prevtestchar . $testchar; # include the previous character which may have stumbled
      } elsif ($userchar ne $testchar) { # mistaken char
         $r->{mistakenchars}->add($testchar, 1);
         $r->{successbypos}->add($i, 0);
         $r->{focuschars} .= $userchar . $testchar . $testchar;
      } else {
         $r->{successbypos}->add($i, 1);
      }

      $prevtestchar = $testchar;

      my $reaction = $usertime - $endchartime;

      if ($reaction < $minimumreaction and $userchar eq '_') {
         $reaction = $defaultreaction;  # avoid suspicious reactions from skewing stats
      }

      if ($e->{measurecharreactions}) {
         $r->{reactionsbychar}->add($testchar, $reaction);
         $r->{reactionsbypos}->add($i, $reaction);
      }
   }

   my ($userspace, $userspacetime) = $userinputref->chardata($testwordlength);

   # measure reaction from when next character would have been expected
   my $endspacetime = $teststatsref->{endtime};
   my $spacereaction = $userspacetime - $endspacetime;

   $r->{pulsecount} += 4; # for whole session

   if ($userspacetime > 0) {
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
      }
   }
}

sub marktest {
   my $self = shift;
   my $e = $self->{dlg}->{e};

   my $r = {}; # results structure

   $self->{dlg}->{d}->Contents(''); # clear the text display

   # get test report from player
   my $statshandle;
   open ($statshandle, $mp2statsfile);

   my @testwords = ();
   my $testword = Word->createfromfile($statshandle);

   # read test and user word structures from formatted records
   while ($testword->{complete}) {
      # if exercise was terminated early, ignore any test content after that time
      # allow up to a second of user anticipation on last word
      if ($self->{abortpendingtime} > 0 and $testword->{endtime} > $self->{abortpendingtime} + 1) {
         last;
      }

      push(@testwords, $testword);
      $testword = Word->createfromfile($statshandle);
   }

   close($statshandle);
   unlink($mp2statsfile);

   $r->{testwordcnt} = scalar(@testwords);
   $r->{duration} = time() - $self->{starttime};
   $r->{successes} = 0;
   $r->{pulsecount} = 0;
   $r->{nonblankcharcount} = 0;
   $r->{testwordtext} = [];
   $r->{markedwords} = '';
   $r->{focuswords} = '';
   $r->{focuschars} = '';

   $r->{reactionsbychar} = Histogram->new;
   $r->{reactionsbypos} = Histogram->new;
   $r->{missedchars} = Histogram->new;
   $r->{mistakenchars} = Histogram->new;
   $r->{successbypos} = Histogram->new;

   return if ($r->{testwordcnt} == 0); # possible if aborted early

   my @testwordix = (0 .. ($r->{testwordcnt} - 1)); # set of test word indexes

   foreach (@testwordix) {
      push(@{$r->{testwordtext}}, $testwords[$_]->wordtext);
   }

   # re-align words in case user missed a space and combined two words
   my $iuw = 0;

   foreach (@testwordix) {
      last unless defined $self->{userwords}->[$iuw];

      my (@newwords) = $self->{userwords}->[$iuw]->split($testwords[$_]->wordtext);
      my $newcnt = scalar(@newwords);

      if ($newcnt == 2) {
         # replace original word with two new ones
          splice(@{$self->{userwords}}, $iuw, 1, @newwords);
      }

      $iuw += $newcnt;
   }

   # re-align words in case user missed a whole word but then successfully resynced
   if ($e->{repeatcnt} == 0) {
      # only use if not repeating test words, which can cause mis-alignment
      my $previoususerwordtext = '';

      foreach (@testwordix) {
         last unless defined $self->{userwords}->[$_];

         my $userwordtext = $self->{userwords}->[$_]->wordtext;
         my $testwordtext = $testwords[$_]->wordtext;

         if (($userwordtext ne '') and ($testwordtext ne $userwordtext) and ($testwordtext eq $previoususerwordtext)) {
            # insert dummy user word with zero times - no reactions will be processed
            splice(@{$self->{userwords}}, $_ - 1, 0, Word->createdummy(length($testwordtext)));
            $userwordtext = $previoususerwordtext;
         }

         $previoususerwordtext = $userwordtext;
      }
   }

   # re-align characters in words in case some missed
   foreach (@testwordix) {
      if (defined $self->{userwords}->[$_]) {
         $self->{userwords}->[$_]->align($testwords[$_]->wordtext);
      }
   }

   # report detailed test performance for all words
   print "\nReport fields: testchar, pulsecount, userchar, reaction(ms), typingtime(ms)\n\n";

   foreach (@testwordix) {
      print $testwords[$_]->report($self->{userwords}->[$_]), "\n";

   }

   # there might still be less words entered by user than expected. To avoid skewing statistics, don't mark any missed at the end
   foreach (@testwordix) {
      last unless defined $self->{userwords}->[$_];
      # analyse word characters
      $self->markword($self->{userwords}->[$_], $testwords[$_], $r);
   }

   # summary of test with corrections shown
   foreach (@testwordix) {
      my $testwordtext = $testwords[$_]->wordtext;
      my $userwordtext = '';

      if (defined $self->{userwords}->[$_]) {
         $userwordtext = $self->{userwords}->[$_]->wordtext;
      }

      $r->{markedwords} .= "$userwordtext ";

      if ($userwordtext ne $testwordtext) {
         $r->{markedwords} .= "# [$testwordtext] ";
      }
   }

   # words to focus on next time (don't include any not attempted at end)
   my $prevtestwordtext = '';

   foreach (@testwordix) {
      my $testwordtext = $testwords[$_]->wordtext;
      last unless defined $self->{userwords}->[$_];

      my $userwordtext = $self->{userwords}->[$_]->wordtext;

      if ($userwordtext ne $testwordtext) {
         if ((not $e->{syncafterword}) and ($prevtestwordtext ne '')) {
            $r->{focuswords} .= "$prevtestwordtext "; # a likely cause of error
            $prevtestwordtext = ''; # don't add twice
         }

	 $r->{focuswords} .= "$testwordtext ";
      } else {
         $prevtestwordtext = $testwordtext;
      }
   }

   return $r;
}

sub playText {
   my $self = shift;
   my $e = $self->{dlg}->{e};
   return if $e->{running};

   my $ptext = $self->{dlg}->{d}->Contents;

   if ($ptext eq '') {
      $ptext = $self->generateText();
   }

   $self->openPlayer(1); # multi-line text mode
   $self->writePlayer("=   $ptext");
   $self->closePlayer;

   if ($self->{dlg}->{d}->Contents eq '') {
      $self->{dlg}->{d}->Contents($ptext);
   }
}

sub flashText {
   my $self = shift;
   my $e = $self->{dlg}->{e};
   return if $e->{running};
   $e->{running} = 1;

   my $ftext = $self->{dlg}->{d}->Contents;

   if ($ftext eq '') {
      $ftext = $self->generateText();
   }

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
   $e->{running} = undef;

   if ($self->{dlg}->{d}->Contents eq '') {
      $self->{dlg}->{d}->Contents($ftext);
   }
}

sub generateText {
   my $self = shift;
   my $e = $self->{dlg}->{e};
   return if $e->{running};

   my $avgwordlength = ($e->{maxwordlength} + $e->{minwordlength}) / 2;
   ($avgwordlength > 1) or ($avgwordlength = 5);
  
   # the space at the end of a word is approximately half an average character in duration
   my $genwords = $e->{practicetime} * $e->{effwpm} * 5.5 / ($avgwordlength + 0.5 * (1 + int($e->{extrawordspaces})));

   my $text = '';

   for (my $i = 0; $i < $genwords; $i++) {
      $text .= $self->{twg}->chooseWord . ' ';
   }

#  chop($text); # remove final blank 
  return $text;
}

sub calibrate {
   my $self = shift;
   $self->openStandardPlayer;
   # Play a standard tune-up message at "A" pitch and 20 wpm and -20dB amplitude

   $self->writePlayer("000");
   $self->closePlayer;

   $self->openPlayer;
   # now play a standard message at the selected pitch and wpm 

   $self->writePlayer("paris paris");
   $self->closePlayer;
}

sub stopAuto {
   my $self = shift;
   my $e = $self->{dlg}->{e};
   return unless $e->{running};
   $e->{running} = undef;

   $self->{dlg}->stopusertextinput;
   $self->closePlayer($self->{abortpendingtime} > 0); # force if abort requested

   if ($self->{starttime} > 0) {
      my $res = $self->marktest();

      if (defined $res and $res->{nonblankcharcount} > 0) {
         ResultsDialog::show($res, $self->{dlg});
         $self->{dlg}->{d}->Contents($res->{focuswords}); # retain failed test words
         $e->{autoextraweights} = $res->{focuschars};
      } else {
         $self->{dlg}->{d}->Contents(join ' ', @{$res->{testwordtext}});
      }
   }

   $self->{dlg}->setControlState('normal');

   if ($e->{dictsize} == 0) {
      $e->{dictsize} = 9999; # avoid lock ups 
   }
}

sub autoweight {
   my $self = shift;
   my $e = $self->{dlg}->{e};
   return if $e->{running};

   my $xweights = $e->{autoextraweights}; 
   $xweights =~ s/[ _]//g; # blanks are valid characters but should not be picked
   $e->{xweights} = $xweights;
}

sub syncflush {
   my $self = shift;
   my $e = $self->{dlg}->{e};

   # Check that previous playing has finished so timings are accurate
   my $pollctr;

   for ($pollctr = 0; $pollctr < 50; $pollctr++) {
      last if (-f $mp2readyfile);
      usleep(20000); # microseconds
   }

   unlink($mp2readyfile) if -f $mp2readyfile;
}

1;

