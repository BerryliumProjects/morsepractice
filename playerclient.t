#! /usr/bin/perl

use lib '.';
use Test::Simple tests=>10;
use playerclient;
use Data::Dumper;

my $e = {wpm=>25, effwpm=>15, pitch=>600, attenuation=>10, pitchshift=>0, dashweight=>5, extrawordspaces=>2};
print Dumper $e;

my $pc = PlayerClient->init;
ok(defined($pc),'client created');

$pc->openPlayer($e); # not text mode
ok(defined($pc->{MP}), 'player opened');
ok(1, 'play cq cq dx');
$pc->writePlayer('cq cq');
$pc->syncflush;
$pc->writePlayer('dx');
ok(1, 'play at slower rate');
$pc->adjustSpeed(18,12);
$pc->writePlayer('qrs pse');
$pc->closePlayer;
ok(!(defined $pc->{MP}), 'player closed');

ok(1, 'play codex as text');
PlayerClient->playText($e, 'codex');

ok(1, 'play calibration test with initial wpm/effwpm 20/18');

$e->{wpm} = undef;
$e->{effwpm} = undef;
$e->{initwpm} = 20;
$e->{initeffwpm} = 18;
PlayerClient->calibrate($e);

$e->{pitchshift} = 1;
ok(1, 'play calibration test with pitch shift 1 semitone');
PlayerClient->calibrate($e);

$e->{playratefactor} = 1.1;
ok(1, 'play calibration test with 1.1 play rate adjustment');
PlayerClient->calibrate($e);

ok(1, 'play calibration test with default standard settings');
PlayerClient->calibrate();

