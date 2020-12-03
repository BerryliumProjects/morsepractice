package TestWordGenerator;

use strict;
use warnings;
use Data::Dumper;

sub new {
   my $class = shift;
   my $minlength = shift;
   my $maxlength = shift;
   my $repeats = shift;

   $repeats = 0 unless defined($repeats);

   my $self = {testwords => [], minlength => $minlength, maxlength => $maxlength, repeats => $repeats, size => 0, queue => [], prevword => ''};
   bless($self, $class);
   return $self;
}


sub addDictionary {
   my $self = shift;
   my $wordfile = shift;
   my $offset = shift;
   my $maxcount = shift;

   my $c = 0; # count of words added

   if (open(WL, $wordfile)) {
      while (defined(my $word = <WL>)) {
         # trim leading/trailing space but keep embedded spaces within phrases
         chomp $word;
         $word =~ s/^ +//;
         $word =~ s/ +$//;

         # don't apply length constraints to phrases
         if ($word =~ ' ' or (length($word) >= $self->{minlength} and length($word) <= $self->{maxlength})) {
            $c++;
            if ($c > $offset) {
               $self->addWord($word);
               last if ($c >= $offset + $maxcount);
            }
         }
      }
   }

   close(WL);
}


sub addRandom {
   my $self = shift;
   my $weightedcharlist = shift;
   my $count = shift;

   my $charlistlength = length($weightedcharlist);

   for (my $i = 0; $i < $count; $i++) {
      my $wordlength = int(rand($self->{maxlength} - $self->{minlength} + 1)) + $self->{minlength};
      my $word = '';

      foreach (1 .. $wordlength) {
         $word .= substr($weightedcharlist, int(rand($charlistlength)), 1);
      }

      $self->addWord($word);
   }
}


sub addPhonemes {
   # add all selected phonemes, as there aren't many
   my $self = shift;

   if (open(PL, 'phonemelist.txt')) {
      while (defined(my $word = <PL>)) {
         # trim space
         chomp $word;
         $word =~ s/\s//g;

         if (length($word) >= $self->{minlength} and length($word) <= $self->{maxlength}) {
            $self->addWord($word);
         }
      }
   }

   close(WL);
}


sub addPseudo {
   my $self = shift;
   my $count = shift;

   my $vowels = readElements('vowels.txt'); # ref to 3 arrays
   my $consonants = readElements('consonants.txt'); # ref to 3 arrays

   for (my $i = 0; $i < $count; $i++) {
      # choose approximate word length less than but not equal to the maximum

      my $targetwordlength = int(rand($self->{maxlength} - $self->{minlength})) + $self->{minlength};
      my $word = '';
      my $wordlength = 0;
      my $wantvowel = (int(rand(5)) == 0); # choose initial vowel 20% of the time

      # alternate between vowel and consonant elements until the target word length is reached or exceeded
      while($wordlength < $targetwordlength) {
         my $elements = ($wantvowel ? $vowels : $consonants);
         $word .= chooseElement($elements, $wordlength, $targetwordlength);

         $wantvowel = not $wantvowel;
         $wordlength = length($word);
      }

      # truncate the word to the maximum length - assume first letter of final element is also ok at end of word
      $word = substr($word, 0, $self->{maxlength});
      $self->addWord($word);
   }
}


sub addCallsign {
   my $self = shift;
   my $europrefix = shift;
   my $complex = shift;
   my $count = shift;

   my @alpha;

   foreach ('a' .. 'z') {
      push @alpha, $_;
   }

   my @num;

   foreach ('0' .. '9') {
      push @num, $_;
   }

   my @alphanum = @alpha;
   push @alphanum, @num;

   for (my $i = 0; $i < $count; $i++) {
      my @prefixes;

      if ($europrefix and open(EUROPFX, "europeanprefixes.txt")) {
            my @europrefixes = <EUROPFX>;
            close(EUROPFX);
            chomp(@europrefixes);

         for (my $j = 0; $j<2; $j++) {
            my $prefix = $europrefixes[int(rand(scalar(@europrefixes)))];
            $prefix =~ s/\t.*//;
            push @prefixes, $prefix;
         }
      } else {
         for (my $j = 0; $j<2; $j++) {
            my $prefix = $alphanum[int(rand(36))];

            if ($prefix =~ /\d/) {
               # prefixes starting with a digit must also include a letter
               $prefix .= $alpha[int(rand(26))];
            } elsif (rand(100) > 30) {
               # prefixes starting with a letter may be length 1 or 2
               $prefix .= $alpha[int(rand(26))];
            }

            push @prefixes, $prefix;
         }
      }

      my $word = $prefixes[0];

      if ($complex) {
         # extra operating country prefix
         $word .= '/' . $prefixes[1];
      }

      # rest of local callsign
      $word .= $num[int(rand(10))];
      $word .= $alpha[int(rand(26))];
      $word .= $alpha[int(rand(26))];

      if (rand(100) > 25) {
         # make some callsigns include only 2 serial characters
         $word .= $alpha[int(rand(26))];
      }

      if ($complex) {
         my $suffixpc = rand(100);

         if ($suffixpc > 80) {
            # portable
            $word .= '/p'
         } elsif ($suffixpc > 70) {
            # mobile
            $word .= '/m'
         } elsif ($suffixpc > 65) {
            # alternative qth
            $word .= '/a'
         } elsif ($suffixpc > 63) {
            # maritime mobile
            $word .= '/mm'
         } elsif ($suffixpc > 60) {
            # Jota
            $word .= '/j'
         } # otherwise no suffix
      }

      $self->addWord($word);
   }
}


sub chooseElement {
   my $elements = shift;
   my $wordlength = shift;
   my $targetwordlength = shift;

   # determine if need an element suitable for the beginning / middle / end of a word
   my $elementPosition =
      ($wordlength == 0) ? 'b' :
      ($wordlength < $targetwordlength -2) ? 'm' :
      'e';

   my $elementList = $elements->{$elementPosition};
   my $elementIndex = int(rand(scalar(@{$elementList})));
   return $elementList->[$elementIndex];
}


sub addWord {
   my $self = shift;
   my $word = shift;

   if (defined $word) {
      $word =~ s/^\s//g;
      $word =~ s/\s$//g;

      if ($word ne '') {
         push(@{$self->{testwords}}, lc($word));
         $self->{size}++;
      }
   }
}


sub readElements {
   my $file = shift;

   my $elements = {b => [], m => [], e => []}; # lists suitable for beginning, middle and end of a word

   open(EFILE, $file) or
      die "Unable to read $file";

   my @elementlines = <EFILE>;
   chomp(@elementlines);
   close(EFILE);

   (@elementlines > 2) or
      die "Not enough elements in $file";

   foreach (@elementlines) {
      my ($validPositions, $elementchars, $elementcnt) = split(/\t/);
      next unless (defined $elementcnt);

      unless ($elementcnt > 0) {
         $elementcnt = 1;
      }

      foreach my $position ('b', 'm', 'e') {
         if ($validPositions =~ $position) {
            foreach (1 .. $elementcnt) {
               push(@{$elements->{$position}}, $elementchars); # add to appropriate list
            }
         }
      }
   }

   return $elements;
}


sub chooseWord {
   my $self = shift;

   my $prevword = $self->{prevword};
   my $word;
   my $maxtries = 5;

   ($self->{size} > 0) or
      return '='; # default if list is empty

   if (@{$self->{queue}} == 0) {
      my $phrase = '';

      for (1 .. $maxtries) {
         $phrase = $self->{testwords}->[int(rand($self->{size} - 0.0001))];
         last if ($phrase=~/ / or $phrase ne $prevword); # try to avoid consecutive duplicates of single words
      }

      if ($phrase=~/ /) {
         foreach my $word (split(/ /, $phrase)) {
            push @{$self->{queue}}, $word;
         }
      } else { # form a phrase by repeating single word if required
         for (my $reps = 0; $reps <= $self->{repeats}; $reps++) {
            push @{$self->{queue}}, $phrase;
         }
      }
   }

   return $self->{prevword} = shift @{$self->{queue}};
}


sub plainEnglishWeights {
   my $self = shift;
   my $charset = shift;

   my $xweights = '';

   # use an approximate discrete frequency distribution
   # infrequent letters are given a base likelihood of 1% to aid practice
   foreach (split(//, $charset)) {
      if (/[e]/) {$xweights .= $_ x 11;}
      elsif (/[t]/) {$xweights .= $_ x 8;}
      elsif (/[a]/) {$xweights .= $_ x 7;}
      elsif (/[ino]/) {$xweights .= $_ x 6;}
      elsif (/[hrs]/) {$xweights .= $_ x 5;}
      elsif (/[dl]/) {$xweights .= $_ x 3;}
      elsif (/[cu]/) {$xweights .= $_ x 2;}
      elsif (/[fgmpwy]/) {$xweights .= $_;}
   }

   return $xweights;
}

1;

