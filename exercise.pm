#! /usr/bin/perl 
use strict;
use warnings;
package Exercise;

use Data::Dumper;
use IO::Handle;
use Time::HiRes qw(time usleep);

use lib '.';

use testwordgenerator;
use histogram;
use resultsdialog;
use word;
use results;
use playerclient;

sub init {
   my $class = shift;

   my $self = {};
   bless($self, $class);
   $self->{dlg} = shift;
   $self->{twg} = undef;
   $self->{starttime} = 0;
   $self->{abortpendingtime} = 0;
   $self->{userwords} = undef;
   $self->{userwordinput} = undef;
   $self->{testattempted} = undef;
   $self->{MP} = undef;
   $self->{running} = undef;
   $self->{sessionPB} = 0; # highest score for this exercise session
   return $self;
}

sub setkochlevel {
   my $self = shift;
   my $e = $self->{dlg}->{e};
   return if $e->{running};

   $e->{keylist} = CharCodes->getCharsKochOrder($e->{kochlevel});
   $self->setexweights();
}

sub setexweights {
   my $self = shift;
   my $e = $self->{dlg}->{e};
   return if $e->{running};

   if ($e->{userelfreq}) {
      if ($e->{kochlevel} > 1) {
         $e->{xweights} = CharCodes->getKochWeights($e->{kochlevel});
      } else {
         $e->{xweights} = TestWordGenerator->plainEnglishWeights($e->{keylist});
      }
   } else {
      $e->{xweights} = '';
   }
}

sub prepareTest {
   my $self = shift;
   my $e = $self->{dlg}->{e};
   return if $e->{running};

   $e->{autoextraweights} = '';
   $e->{wpm} = $e->{initwpm};
   $e->{effwpm} = $e->{initeffwpm};

   $self->{twg} = TestWordGenerator->new($e->{minwordlength}, $e->{maxwordlength}, $e->{repeatcnt});
   my $extype = $e->{extype};
   # build selected word list considering complexity and min/max word length

   if ($extype =~ /Single|Random|Numbers/) {
      $self->{twg}->addRandom($e->{keylist} . $e->{xweights}, 200);
   } elsif ($extype =~ 'Pseudo words') {
      $self->{twg}->addPseudo(200);
   } elsif ($extype eq 'Phonemes') {
      $self->{twg}->addPhonemes();
   } elsif ($extype eq 'QSO terms') {
      $self->{twg}->addDictionary('qsowordlist.txt', 0, 999);
   } elsif ($extype eq 'QSO phrases') {
      $self->{twg}->addDictionary('qsophrases.txt', 0, 999);
   } elsif ($extype eq  'Common words') {
      $self->{twg}->addDictionary('wordlist100.txt', 0, 999);
   } elsif ($extype eq 'Dictionary words') {
      $self->{twg}->addDictionary('wordlist-complexity.txt', $e->{dictoffset}, $e->{dictsize}, $e->{includechars});
   } elsif ($extype eq 'Callsigns') {
      if ($e->{usescalls}) { # include simple callsigns
         $self->{twg}->addCallsign($e->{europrefix}, 0, 200);
      } else { # include some suffixes after simple callsigns
         $self->{twg}->addCallsign($e->{europrefix}, 1, 200);
      }

      if ($e->{useicalls}) { # include some international prefixes, some also with suffixes
         $self->{twg}->addCallsign($e->{europrefix}, 2, 50);
      }
   }

   if ($e->{usespecified}) {
      my @specwords = split(/\s+/, $self->{dlg}->{d}->Contents);
      my $probability = 0.3;
      $self->{twg}->addSpecified($probability, @specwords);
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

   if (! $e->{syncafterword}) {
      $e->{retrymistakes} = 0; # can't retry unless syncing after each word
      $e->{autoincrement} = 0; # can only change speed at pauses
   }

   unless ($e->{practicetime} =~ /^[\d\.]+$/ and $e->{practicetime} > 0){
      $e->{practicetime} = 2;
   }
}


sub startAuto {
   my $self = shift;
   my $e = $self->{dlg}->{e};
   return if $e->{running};
   $e->{running} = 1;


   $self->{dlg}->{d}->Contents('');
   $self->{dlg}->{d}->focus;
   $self->{dlg}->setControlState('disabled');
   $self->{abortpendingtime} = 0;
   Word->debounce('');
   $self->{userwords} = [];
   $self->{userwordinput} = Word->new;
   $self->{testwordcount} = 0;
   $self->{testattempted} = 0;

   PlayerClient->playText($e, ''); # plays = and some space, so hearer knows what speed to expect
   $self->{MP} = PlayerClient->init;
   $self->{MP}->openPlayer($e);

   $self->{starttime} = undef;

   $self->{dlg}->startusertextinput;

   if ($e->{syncafterword}) {
      $self->{MP}->writePlayer($self->{twg}->chooseWord);
   } else {
      my $testtext = $self->generateText();
      my @testtext = split(/ /, $testtext);
      $self->{testwordcount} = scalar(@testtext); # target word count
      $self->{MP}->writePlayer($testtext);
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
      $self->{MP}->syncflush;

      if (($e->{practicetime} * 60) < (time() - $self->{starttime})) {
         $self->{abortpendingtime} = time();
      } else {
         my $testword = $self->{twg}->{prevword};
         my $userword = $self->{userwordinput}->wordtext;

         if ($userword ne $testword) {
            if ($e->{retrymistakes}) {
               $self->{dlg}->{d}->insert('end', '# ');
               $testword = $self->{twg}->chooseWord(1); # extra retry
            } else {
               $testword = $self->{twg}->chooseWord;
            }

            if ($e->{autoincrement}) {
               if ($e->{initwpm} lt $e->{wpm}) {
                  # keep character wpm at least at initial wpm - stretch gaps if need to go below that. There is no lower limit on effective wpm.
                  $e->{wpm}--;
               }

               $e->{effwpm}--;
               $self->{MP}->adjustSpeed($e->{wpm}, $e->{effwpm});
            }
         } else {
            $testword = $self->{twg}->chooseWord;

            if ($e->{autoincrement}) {
               if ($e->{effwpm} eq $e->{wpm}) {
                  $e->{wpm}++; # once extra spacing is removed, increase character speed as well
               }

               $e->{effwpm}++;
               $self->{MP}->adjustSpeed($e->{wpm}, $e->{effwpm});
            }
         }

         $self->{MP}->writePlayer($testword);
      }
   } else {
      if (scalar(@{$self->{userwords}}) + 1 >= $self->{testwordcount}) {
         $self->{abortpendingtime} = time();
      }
   }

   push(@{$self->{userwords}}, $self->{userwordinput});

   if (length($self->{userwordinput}->wordtext) > 0) {
      $self->{testattempted} = 1;
   }
}

sub marktest {
   my $self = shift;
   my $e = $self->{dlg}->{e};

   $self->{dlg}->{d}->Contents(''); # clear the text display

   # get test report from player
   my $statshandle = PlayerClient->openStats or die "Missing test word stats file";

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

   PlayerClient->closeStats($statshandle);

   my $r = Results->init(\@testwords, $self->{starttime}, $e); # results of test evaluation

   return $r unless $self->{testattempted};

   # re-align words in case user missed a space and combined two words
   my $iuw = 0;
   my @testwordix = (0 .. ($r->{testwordcnt} - 1)); # set of test word indexes

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

   $r->markwords($self->{userwords}, \@testwords);
   $r->calculateScore();

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

   PlayerClient->playText($e, $ptext);

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

sub stopAuto {
   my $self = shift;
   my $e = $self->{dlg}->{e};
   return unless $e->{running};
   $e->{running} = undef;

   $self->{dlg}->stopusertextinput;
   $self->{MP}->closePlayer($self->{abortpendingtime} > 0); # force if abort requested
   $self->{MP} = undef;

   if ($self->{starttime} > 0) {
      my $res = $self->marktest();

      if (defined $res and $res->{nonblankcharcount} > 0) {
         ResultsDialog::show($res, $self->{dlg});
         $self->{dlg}->{d}->Contents($res->{focuswords}); # retain failed test words
         $e->{autoextraweights} = $res->{focuschars};

         if ($res->{score} > $e->{sessionPB}) {
            $e->{sessionPB} = $res->{score};
         }
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

1;

