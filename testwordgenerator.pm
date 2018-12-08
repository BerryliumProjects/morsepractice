package TestWordGenerator;

use strict;
use warnings;
use Data::Dumper;

sub new {
   my $class = shift;
   my $minlength = shift;
   my $maxlength = shift;
   my $self = {testwords => [], minlength => $minlength, maxlength => $maxlength, size => 0};
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
         chomp $word;
         $word =~ s/ //g;

         if (length($word) >= $self->{minlength} and length($word) <= $self->{maxlength}) { 
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
      my $wantvowel = (int(rand(2)) > 0); # choose initial type of element

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
   push(@{$self->{testwords}}, lc($word));
   $self->{size}++;
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
   my $prevword = shift;

   my $word;
   my $maxtries = 5;

   ($self->{size} > 0) or
      return '='; # default if list is empty

   for (1 .. $maxtries) {
      $word = $self->{testwords}->[int(rand($self->{size} - 0.0001))];
      last if ($word ne $prevword); # try to avoid consecutive duplicates
   }

   return $word;
}


sub plainEnglishWeights {
   my $self = shift;
   my $charset = shift;

   my $xweights = '';

   # use an approximate discrete frequency distribution
   foreach (split(//, $charset)) {
      if (/[e]/) {$xweights .= $_ x 10;}
      elsif (/[t]/) {$xweights .= $_ x 7;}
      elsif (/[ao]/) {$xweights .= $_ x 6;}
      elsif (/[ins]/) {$xweights .= $_ x 5;}
      elsif (/[hrw]/) {$xweights .= $_ x 4;}
      elsif (/[dly]/) {$xweights .= $_ x 3;}
      elsif (/[ck]/) {$xweights .= $_ x 2;}
      elsif (/[fgmpu]/) {$xweights .= $_;}
   }

   return $xweights;
}

1;

