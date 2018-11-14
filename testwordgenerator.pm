#!/usr/bin/perl 
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

   my ($vcount, @vowels) = readElements('vowels.txt');
   my ($ccount1, @consonants1) = readElements('consonants1.txt');
   my ($ccount2, @consonants2) = readElements('consonants2.txt');
   my ($ccount3, @consonants3) = readElements('consonants3.txt');

   for (my $i = 0; $i < $count; $i++) {
      # choose approximate word length less than but not equal to the maximum

      my $wordlength = int(rand($self->{maxlength} - $self->{minlength})) + $self->{minlength};
      my $word = '';

      my $wantvowel = (int(rand(2)) > 0);
      # choose if starting with vowel element  or consonant element

      # alternate between vowel and consonant elements until the target word length is reached or exceeded
      while(length($word) < $wordlength) {
         if ($wantvowel) {
            $word .= $vowels[int(rand($vcount))]; 
         } elsif (length($word) == 0) {
            $word .= $consonants1[int(rand($ccount1))];
         } elsif (length($word) >= $wordlength-2) {
            $word .= $consonants3[int(rand($ccount3))];
         } else {
            $word .= $consonants2[int(rand($ccount2))];
         }

         $wantvowel = not $wantvowel;
      }
      
      # truncate the word to the maximum length
      $word = substr($word, 0, $self->{maxlength});
      $self->addWord($word);
   }
}
    

sub addWord {
   my $self = shift;
   my $word = shift;
   push(@{$self->{testwords}}, lc($word));
   $self->{size}++;
}


sub readElements {
   my $file = shift;

   open(EFILE, $file) or
      die "Unable to read $file";

   my @elements = <EFILE>;
   chomp(@elements);
   close(EFILE);

   my $ecount = scalar(@elements);
   ($ecount > 2) or 
      die "Not enough elements in $file";

   return ($ecount, @elements);
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
      if (/[e]/) {$xweights .= $_ x 11;}
      elsif (/[taoin]/) {$xweights .= $_ x 7;}
      elsif (/[shr]/) {$xweights .= $_ x 5;}
      elsif (/[dl]/) {$xweights .= $_ x 3;}
      elsif (/[cfghpuwy]/) {$xweights .= $_;}
   }

   return $xweights;
}

1;

