package ResultsDialog;

sub show {
   my $res = shift;
   my $mdlg = shift;

   my $e = $mdlg->{e};
   my $rw = $mdlg->{w}->DialogBox(-title=>'Results', -buttons=>['OK']); # results window
   my $rwdf = DialogFields->init($rw);
   populateresultswindow($rwdf);

   # statistics used: 
   #   words:  testwordcnt, successes
   #   chars:  nonblankcharcount, mistakenchars, missedchars
   #   pulses: pulsecount
   #   reactions: reactionsbychar, reactionsbypos - reactions recorded for bad chars but not missed chars

   my $successrate = $res->{successes} / $res->{testwordcnt};
   my $missedcharcnt = $res->{missedchars}->grandcount;
   my $mistakencharcnt = $res->{mistakenchars}->grandcount;
   my $charsuccessrate = 1 - ($missedcharcnt + $mistakencharcnt) / $res->{nonblankcharcount};
   my $avgpulsecnt = $res->{pulsecount} / ($res->{nonblankcharcount} + $res->{testwordcnt});

   my $re = $rwdf->entries; # gridframe control values
   $re->{duration} = sprintf('%i', $res->{duration});
   $re->{wordreport} = sprintf('%i%% (%i / %i)', $successrate * 100, $res->{successes}, $res->{testwordcnt});
   $re->{charreport} = sprintf('%i%% (%i missed, %i wrong / %i)', $charsuccessrate * 100, $missedcharcnt, $mistakencharcnt, $res->{nonblankcharcount});
   $re->{missedchars} = join('', @{$res->{missedchars}->keys});
   $re->{mistakenchars} = join('', @{$res->{mistakenchars}->keys});
   $re->{pariswpm} = sprintf('%.1f', ($res->{pulsecount} / 50) * $charsuccessrate / ($res->{duration} / 60)); # based on elements decoded
   $re->{charswpm} = sprintf('%.1f', ($e->{effwpm} * $charsuccessrate)); # based on characters decoded
   $re->{relcharweight} = sprintf('%i%%', $avgpulsecnt / (50 / 6) * 100); # as percentage

   my $stdcharpausetime = 2 * 1.2 / $e->{wpm}; # 2 pulses
   # using standard average word length 5, 6 extra pauses per (word + space)
   my $extracharpausetime = 60 / 6 * (1 / $e->{effwpm} - 1 / $e->{wpm});
   $re->{charpausefactor} = sprintf('%i%%', $extracharpausetime / $stdcharpausetime * 100); # as percentage

   # Report slowest average reaction times by character
   my %avgreactionsbychar = %{$res->{reactionsbychar}->averages};
   my @worstchars = sort {$avgreactionsbychar{$b} <=> $avgreactionsbychar{$a}} (keys %avgreactionsbychar);

   my $worstcharsreport = '';

   if (@worstchars) {
      my $worstcount = 0;

      foreach my $ch (@worstchars) {
         $worstcharsreport .= sprintf ("\t%s\t%i ms\n", $ch, $avgreactionsbychar{$ch} * 1000 + 0.5);
         last if ($worstcount++ > 4);
      }
   }

   $rwdf->{controls}->{worstchars}->Contents($worstcharsreport);

   # Report average reaction times by position in word
   my %avgreactionsbypos = %{$res->{reactionsbypos}->averages};
   my @worstcharpos = sort keys %avgreactionsbypos;

   my $worstcharposreport = '';

   if ($e->{measurecharreactions}) {
      if (@worstcharpos) {
         foreach my $pos (@worstcharpos) {
            $worstcharposreport .= sprintf ("\t%s\t%i ms\n", $pos, $avgreactionsbypos{$pos} * 1000 + 0.5);
         }
      }
   } else {
      my $wordspacetime = 4 * (1 + int($e->{extrawordspaces})) * 1.2 / $e->{wpm};
      # reactions are from earliest opportunity to detect end of word, not from end of gap if extra spaces have been inserted
      $worstcharposreport .= sprintf("Word start\t%i ms\n", $avgreactionsbypos{-2} * 1000 + 0.5);
      $worstcharposreport .= sprintf("Word end  \t%i ms\n", $avgreactionsbypos{-1} * 1000 + 0.5);
      $worstcharposreport .= sprintf("Space time\t%i ms\n", $wordspacetime * 1000 + 0.5);
   }

   $rwdf->{controls}->{worstcharpos}->Contents($worstcharposreport);

   # Report success rate by position in word
   my %avgsuccessbypos = %{$res->{successbypos}->averages};

   my $positionsuccessreport = '';

   foreach my $pos (sort keys %avgsuccessbypos) {
      my $avgsuccessbypospc = int($avgsuccessbypos{$pos} * 100 + 0.5);
      $positionsuccessreport .= sprintf("\t%i\t%i%% (%i / %i)\n", $pos, $avgsuccessbypospc, $res->{successbypos}->keytotal($pos), $res->{successbypos}->keycount($pos));
   }

   $rwdf->{controls}->{positionsuccesses}->Contents($positionsuccessreport);
   $rw->Show;
}



sub populateresultswindow {
   my $rwdf = shift;

   $rwdf->addEntryField('Duration', 'duration', 30, undef, undef, undef, '');
   $rwdf->addEntryField('Word success rate', 'wordreport', 30, undef, undef, undef, '');
   $rwdf->addEntryField('Character success rate', 'charreport', 30, undef, undef, undef, '');
   $rwdf->addEntryField('Missed characters', 'missedchars', 30, undef, undef, undef, '');
   $rwdf->addEntryField('Mistaken characters', 'mistakenchars', 30, undef, undef, undef, '');
   $rwdf->addEntryField('Achieved paris wpm', 'pariswpm', 30, undef, undef, undef, '');
   $rwdf->addEntryField('Achieved character wpm', 'charswpm', 30, undef, undef, undef, '');
   $rwdf->addEntryField('Relative character weight', 'relcharweight', 30, undef, undef, undef, '');
   $rwdf->addEntryField('Inter-character pause factor', 'charpausefactor', 30, undef, undef, undef, '');

   $rwdf->addWideTextField('Slowest reactions by character:', 'worstchars', 5, 35, '', undef, undef, '');
   $rwdf->addWideTextField('Reactions by position:', 'worstcharpos', 10, 35, '', undef, undef, '');
   $rwdf->addWideTextField('Success rate by position:', 'positionsuccesses', 10, 35, '', undef, undef, '');

#    $rwdf->addButtonField('OK', 'ok',  undef, sub{$rwdf->{w}->destroy}, '');
}

1;


