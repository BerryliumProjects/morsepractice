package Word;

use strict;
use warnings;
use Data::Dumper;
use Time::HiRes qw(time usleep);

# constructor: create empty word
sub new {
   my $class = shift;
   my $self = {charstats => [], complete => undef, starttime => 0, endtime => 0};
   bless($self, $class);
   return $self;
}

# constructor: create a new word from a single printable character
sub createfromchar {
   my $class = shift;
   my $ch = shift;
   my $self = $class->new;

   if (defined($ch) and length($ch) == 1 and $ch ne "\b" and $ch ne ' ') {
      $self->append($ch);
      $self->append(' ');
   }

   return $self;
}

# build a word one element at a time. Return true if complete (with terminating space)
sub append {
   my ($self, $ch, $thischtime, $pulsecount) = @_;

   $ch = debounce($ch);

   if (defined ($ch) and length($ch) == 1 and $ch ne "\b" and not $self->{complete}){
      $ch = lc($ch);
      $ch =~ s/\r/ /; # newline should behave like space as word terminator
      
      $thischtime = time() unless defined $thischtime;
      push(@{$self->{charstats}}, {ch => $ch, t => $thischtime, pcnt => $pulsecount});
      $self->{starttime} = $thischtime unless $self->{starttime} > 0;

      if ($ch eq ' ') {
         $self->{complete} = 1;
      } else {
         $self->{endtime} = $thischtime;
      }

      return $self->{complete};
   }
}

# constructor: create a placeholder of underscores and no timings
sub createdummy {
   my $class = shift;
   my $length = shift;

   my $self = $class->new;

   for (1 .. $length) {
      $self->append('_', 0);
   }

   $self->append(' ', 0);
   return $self;
}



# remove the most recently added element from an incomplete word
sub undo {
   my $self = shift;
   
   if (not $self->{complete}) {
      pop (@{$self->{charstats}});

      if (scalar(@{$self->{charstats}}) > 0) {
         $self->{endtime} = $self->{charstats}->[-1]->{t}; # new last element
      } else {
         $self->{starttime} = 0;
         $self->{endtime} = 0;
      }
   }      
}

my $prevchar = ''; # static class member
my $prevchartime = 0;

# static method - discount repeated spaces keyed too closely together
# to prime the debouncer: call with an empty string;
sub debounce {
   my $char = shift;
   my $newchar = $char;
   my $chartime = time();
   
   if ($prevchar ne '') {
      if ($char eq ' ' and $prevchar eq ' ') {
         # ignore a double space if less than 500ms between them
         if ($chartime < $prevchartime + 0.5) {
            $newchar = '';
         }
      }
   }

   $prevchar = $char;
   $prevchartime = $chartime;

   return $newchar;
}
   
# get the word characters (excluding the terminator) as a string
sub wordtext {
   my $self = shift;
   my @charstats = @{$self->{charstats}};
   my $wordlen = scalar(@charstats);
   $wordlen-- if $self->{complete}; # ignore trailing space

   my $wordtext = '';

   for (my $i = 0; $i < $wordlen; $i++) {
      $wordtext .= $charstats[$i]->{ch};
   }

   return $wordtext;
}

# get array of character data. pcnt is only defined for test words, not user words
sub chardata {
   my $self = shift;
   my $index = shift;
   
   my $chardataref = $self->{charstats}->[$index];

   return ($chardataref->{ch}, $chardataref->{t}, $chardataref->{pcnt});
}

# constructor: create word by reading from a file handle, or undef if not possible
sub createfromfile {
   my $class = shift;
   my $handle = shift;
   my $self = $class->new; # empty word

   until (eof($handle) or $self->{complete}) {
      my $teststatsitem = <$handle>;
      chomp $teststatsitem;
      $self->append(split(/\t/, $teststatsitem));
   }

   # add a dummy terminator if not present in file
   if (eof($handle) and not $self->{complete}) {
      $self->append(' ', $self->{endtime}, 4);
   }

   return $self;
}

# if user entry is too short, insert blanks to realign to correct length
sub align {
   my $self = shift;
   my $testword = shift; # reference text   

   my $userword = $self->wordtext;

   my $userlen = length($self->wordtext);
   my $missedcnt = length($testword) - $userlen;
   
   if ($missedcnt > 0) {
      my $difpos = 0;
      # user has missed some characters - find first mismatch
      for ($difpos = 0; $difpos < $userlen; $difpos++) { 
         last if (substr($userword, $difpos, 1) ne substr($testword, $difpos, 1));
      }

      # assume first mismatch is really a gap, and fill it
      my $missedtime = $self->{charstats}->[$difpos]->{t}; # deemed to be entered just before the following character (or terminator)

      for (1 .. $missedcnt) {
         splice(@{$self->{charstats}}, $difpos, 0, {ch => '_', t => $missedtime});
      }
   }
}

# split a single user word into two if it's significantly longer than expected
sub split {
   my $self = shift;
   my $testword = shift;

   my $userlen = scalar(@{$self->{charstats}} - 1); # excluding terminator
   my $testlen = length($testword);

   # assume 1 extra character is a mistake, but more than that is due to a missed space
   if ($userlen > $testlen + 1) {
      my $newword1 = Word->new;
      my $newword2 = Word->new;

      for my $index1 (0 .. $testlen - 1) {
         $newword1->append($self->chardata($index1));
      }

      for my $index2 ($testlen .. $userlen) { # include the terminator
         $newword2->append($self->chardata($index2));
      }

      # terminate the first word
      Word->debounce(''); # reset as last appended a space
      $newword1->append(' ', $newword2->{starttime}, 4);

      return ($newword1, $newword2);
   } # else implicitly return undef
}


sub report {
   # show test word statistics on the terminal, together with any corresponding user entry, reaction and typing rate times
   my $self = shift; # test word
   my $userword = shift;
   my @report;

   my $marktestword = $self->wordtext;
   my $testwordlength = length($marktestword);

   if (defined $userword and length($userword->wordtext) < $testwordlength) {
      return "ERROR: user word is too short\n";
   }

   if (defined $userword) {
      my $prevusertime;
      my $typingtimems;
      my $reactionms;

      for (my $i = 0; $i < $testwordlength; $i++) {
         my ($userchar, $usertime) = $userword->chardata($i);
         my ($testchar, $endchartime, $testpulsecnt) = $self->chardata($i);

         $reactionms = '';
         $typingtimems = '';

         if ($usertime > $endchartime and $userchar ne '_') {
            $reactionms = int(($usertime - $endchartime) * 1000 + 0.5);
         }

         if (defined $prevusertime and $userchar ne '_') {
            $typingtimems = int(($usertime - $prevusertime) * 1000 + 0.5);
         }

         push(@report, sprintf("%1s%5s%2s%5s%5s\n", $testchar, $testpulsecnt, $userchar, $reactionms, $typingtimems));

         # typing time is since previous real keypress, ignoring placeholders
         if ($userchar ne '_') {
            $prevusertime = $usertime;
         }
      }

      # measure end of word reaction from when next character would have been expected
      my ($userspace, $userspacetime) = $userword->chardata($testwordlength);
      my $endspacetime = $self->{endtime};
      $reactionms = int(($userspacetime - $endspacetime) * 1000 + 0.5);

      if (defined $prevusertime) {
         $typingtimems = int(($userspacetime - $prevusertime) * 1000 + 0.5);
      }

      push(@report, sprintf( "%6s%7s%5s\n", 4, $reactionms, $typingtimems));

      # in word recognition mode, note reaction time to start entering word
      # the end of the word can be detected as soon as the next expected element is absent
      my $wordreactionms = int(($userword->{starttime} - $self->{endtime}) * 1000 + 0.5);
      push(@report, sprintf("Word:%8s\n", $wordreactionms));
   } else { # no matching user word - just show test word stats
      for (my $i = 0; $i < $testwordlength; $i++) {
         push(@report, sprintf("%1s%5s\n", $self->{charstats}->[$i]->{ch}, $self->{charstats}->[$i]->{pcnt}));
      }
   }

   return @report;
}

1;
