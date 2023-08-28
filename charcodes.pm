use strict;
use warnings;
package CharCodes;

my %charcodes = (
   
   a=>'.- ',
   b=>'-... ',
   c=>'-.-. ',
   d=>'-.. ',
   e=>'. ',
   f=>'..-. ',
   g=>'--. ',
   h=>'.... ',
   i=>'.. ',
   j=>'.--- ',
   k=>'-.- ',
   l=>'.-.. ',
   m=>'-- ',
   n=>'-. ',
   o=>'--- ',
   p=>'.--. ',
   q=>'--.- ',
   r=>'.-. ',
   s=>'... ',
   t=>'- ',
   u=>'..- ',	
   v=>'...- ',
   w=>'.-- ',
   x=>'-..- ',
   y=>'-.-- ',
   z=>'--.. ',
   0=>'----- ',
   1=>'.---- ',
   2=>'..--- ',
   3=>'...-- ',
   4=>'....- ',
   5=>'..... ',
   6=>'-.... ',
   7=>'--... ',
   8=>'---.. ',
   9=>'----. ',
   '.'=>'.-.-.- ',
   ','=>'--..-- ',
   '?'=>'..--.. ',
   '/'=>'-..-. ',
   '='=>'-...- ',
   ':'=>'---... ',
   ' '=>'  ', 
);

sub getCharCodes {
   return \%charcodes;
}


sub getChars {
   my $ch = join('', sort keys(%charcodes));
   $ch =~ s/ //; # remove blank
   return $ch;
}

sub getCharsKochOrder {
   my $class = shift;
   my $KochLevel = shift;

   if ($KochLevel < 1) {
      # don't use Koch method - show alphanumerically for easier manual choice
      return getChars();
   }

   my $KochSequence = 'kmrsuaptlowi.njef0y,vg5/q9zh38b?427c1d6xi:';

   if ($KochLevel < length($KochSequence)) {
      $KochSequence = substr($KochSequence, 0, $KochLevel);
   }

   # show recently learned characters more frequently
   my $WeightedKochSequence = $KochSequence;

   if ($KochLevel > 4) {
      my $extraWeightprevious = int($KochLevel / 5);
      $WeightedKochSequence .= substr($KochSequence, -2, 1) x $extraWeightprevious;
   }

   if ($KochLevel > 2) {
      my $extraWeightlatest = int($KochLevel / 3);
      $WeightedKochSequence .= substr($KochSequence, -1, 1) x $extraWeightlatest;
   }

   return $WeightedKochSequence;
}


1;
