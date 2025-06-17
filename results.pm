#! /usr/bin/perl 
use strict;
use warnings;
package Results;

#use Tk;
#use Tk::ROText;
#use Tk::DialogBox;

use Data::Dumper;
#use Tk::After;
use Time::HiRes qw(time usleep);

use lib '.';

use histogram;
use word;

# constants
my $defaultreaction = 0.5; # seconds - used if realignment results in < minimum
my $minimumreaction = 0.25; # seconds - below this is suspicious unless character is correct

sub init {
   my $class = shift;
   
   my $self = {};
   bless($self, $class);
 
   my @testwords = @{shift()}; # pass list by reference
   my $starttime = shift;
   $self->{e} = shift;

   $self->{testwordcnt} = scalar(@testwords);
   $self->{duration} = time() - $starttime;
   $self->{successes} = 0;
   $self->{pulsecount} = 0;
   $self->{nonblankcharcount} = 0;
   $self->{testwordtext} = [];
   $self->{markedwords} = '';
   $self->{focuswords} = '';
   $self->{focuschars} = '';

   $self->{reactionsbychar} = Histogram->new;
   $self->{reactionsbypos} = Histogram->new;
   $self->{missedchars} = Histogram->new;
   $self->{mistakenchars} = Histogram->new;
   $self->{successbypos} = Histogram->new;

   if ($self->{testwordcnt} > 0) { # possible if aborted early
      my @testwordix = (0 .. ($self->{testwordcnt} - 1)); # set of test word indexes

      foreach (@testwordix) {
         push(@{$self->{testwordtext}}, $testwords[$_]->wordtext);
      }
   }

   return $self;    
}

sub markword { 
   my $self = shift;

   # find characters in error and mark reactions
   my $userinputref = shift;
   my $teststatsref = shift;

   my $markuserword = '';
   my $marktestword = $teststatsref->wordtext;
   
   if (defined $userinputref) {
      $markuserword = $userinputref->wordtext;
      # there might still be less words entered by user than expected. To avoid skewing statistics, don't mark any missed at the end

      if ($markuserword eq $marktestword) {
         $self->{successes}++;
      }

      my $testwordlength = length($marktestword);
      my $prevtestchar = '';

      for (my $i = 0; $i < $testwordlength; $i++) {
         my ($userchar, $usertime) = $userinputref->chardata($i);
         my ($testchar, $endchartime, $testpulsecnt) = $teststatsref->chardata($i);

         $self->{pulsecount} += $testpulsecnt; # for whole session
         $self->{nonblankcharcount}++;

         if ($userchar eq '_' or $userchar eq '-') { # missed char
            $self->{missedchars}->add($testchar, 1);
            $self->{successbypos}->add($i, 0);
            $self->{focuschars} .= $prevtestchar . $testchar; # include the previous character which may have stumbled
         } elsif ($userchar ne $testchar) { # mistaken char
            $self->{mistakenchars}->add($testchar, 1);
            $self->{successbypos}->add($i, 0);
            $self->{focuschars} .= $userchar . $testchar . $testchar;
         } else {
            $self->{successbypos}->add($i, 1);
         }

         $prevtestchar = $testchar;

         my $reaction = $usertime - $endchartime;

         if ($reaction < $minimumreaction and $userchar eq '_') {
            $reaction = $defaultreaction;  # avoid suspicious reactions from skewing stats
         }

         if ($self->{e}->{measurecharreactions}) {
            $self->{reactionsbychar}->add($testchar, $reaction);
            $self->{reactionsbypos}->add($i, $reaction);
         }
      }

      my ($userspace, $userspacetime) = $userinputref->chardata($testwordlength);

      # measure reaction from when next character would have been expected
      my $endspacetime = $teststatsref->{endtime};
      my $spacereaction = $userspacetime - $endspacetime;

      $self->{pulsecount} += 4; # for whole session

      if ($userspacetime > 0) {
         if ($self->{e}->{measurecharreactions}) {
            $self->{reactionsbychar}->add('>', $spacereaction);
         }

         # also record reaction/histogram by position in word (key:tab-n)
         $self->{reactionsbypos}->add(-1, $spacereaction);

         # if in word recognition mode, note reaction time to start entering word
         # the end of the word can be detected as soon as the next expected element is absent
         if (not $self->{e}->{measurecharreactions}) {
            my $wordreaction = $userinputref->{starttime} - $teststatsref->{endtime};
            $self->{reactionsbypos}->add(-2, $wordreaction);
         }
      }
   }

   # summary of test with corrections shown
   $self->{markedwords} .= "$markuserword ";

   if ($markuserword ne $marktestword) {
      $self->{markedwords} .= "# [$marktestword] ";
   }
}

sub markwords {
   my $self = shift;
   my @userwords = @{shift()}; # pre-aligned characters and words with test
   my @testwords = @{shift()};
   
   my @testwordix = (0 .. ($self->{testwordcnt} - 1)); # set of test word indexes

   # report detailed test performance for all words
   print "\nReport fields: testchar, pulsecount, userchar, reaction(ms), typingtime(ms)\n\n";

   foreach (@testwordix) {
      print $testwords[$_]->report($userwords[$_]), "\n";
      # analyse word characters
      $self->markword($userwords[$_], $testwords[$_]);
   }

   # words to focus on next time (don't include any not attempted at end)
   my $prevtestwordtext = '';

   foreach (@testwordix) {
      my $testwordtext = $testwords[$_]->wordtext;
      last unless defined $userwords[$_];

      my $userwordtext = $userwords[$_]->wordtext;

      if ($userwordtext ne $testwordtext) {
         if ((not $self->{e}->{syncafterword}) and ($prevtestwordtext ne '')) {
            $self->{focuswords} .= "$prevtestwordtext "; # a likely cause of error
            $prevtestwordtext = ''; # don't add twice
         }

         $self->{focuswords} .= "$testwordtext ";
      } else {
         $prevtestwordtext = $testwordtext;
      }
   }

   # add characters with slow responses to focus on
   if ($self->{e}->{measurecharreactions}) {
      my $rbc = $self->{reactionsbychar};
      my $grandcharcount = $rbc->grandcount - $rbc->keycount('>'); # don't include spaces in average

      if ($grandcharcount > 0) {
         my $exavg = ($rbc->grandtotal - $rbc->keytotal('>')) / $grandcharcount;
         my $avg = $rbc->averages;
         
         foreach (@{$rbc->keys()}) {
            if (($_ ne '>') and ($rbc->keycount($_) > 1)) { # ignore spaces and single outliers
               if ($avg->{$_} > 1.2 * $exavg) { # 20% slower than average
                  $self->{focuschars} .= $_;
               }

               if ($avg->{$_} > 1.5 * $exavg) { # very slow responses get additional weight
                  $self->{focuschars} .= $_;
               }
            }
         }
      }
   }
}

1;

