package Histogram;

use strict;
use warnings;
use Data::Dumper;

sub new {
   my $class = shift;
   my $self = {count => {}, total => {}};
   bless($self, $class);
   return $self;
}

sub add {
   # add values to a self accumulator
   my $self = shift;
   my $key = shift;
   my $value = shift;

   if (exists $self->{count}->{$key}) {
      $self->{count}->{$key}++;
      $self->{total}->{$key} += $value;
   } else {
      $self->{count}->{$key} = 1;
      $self->{total}->{$key} = $value;
   }
}

sub grandcount {
   # get number of items added to histogram
   my $self = shift;

   my $count = 0;

   foreach my $key (keys %{$self->{count}}) {
      $count += $self->{count}->{$key};
   }
   
   return $count;
}

sub grandtotal {
   # get total value for all items added to histogram
   my $self = shift;

   my $total = 0;

   foreach my $key (keys %{$self->{total}}) {
      $total += $self->{total}->{$key};
   }
   
   return $total;
}

sub averages {
   # return a reference to a hash of average values (total/count)
   my $self = shift;

   my $averages = {};

   foreach my $key (keys %{$self->{count}}) {
      # count is always at least 1, or the key would not exist
      $averages->{$key} = $self->{total}->{$key} / $self->{count}->{$key};
   }

   return $averages;
}

sub keycount {
   my $self = shift;
   my $key = shift;
   return $self->{count}->{$key};
}

sub keytotal {
   my $self = shift;
   my $key = shift;
   return $self->{total}->{$key};
}

sub keys {
   my $self = shift;
   my %counts = %{$self->{count}};
   my @keys = sort(keys(%counts));
   return \@keys;
}

1;

