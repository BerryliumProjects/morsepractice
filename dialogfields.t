#! /usr/bin/perl

use lib '.';
use Tk;
use Test::Simple tests=>3;
use dialogfields;
use Data::Dumper;

use Tk::ROText;
use Tk::DialogBox;

use Tk::After;


# print Dumper \$d1;

my $w = MainWindow->new();
ok(defined $w, 'Empty window created');
$w->fontCreate('msgbox',-family=>'helvetica', -size=>-14);
my $callback = sub {print "Invoked callback with args @_\n"};
my $df = DialogFields->init($w,$callback,300);
my $e = $df->entries; # gridframe control values
ok(defined $df, 'Empty dialogfields created');

$df->addEntryField('Entry Field', 'entry', 40, 'contents');
$df->addCheckbuttonField('Checkbutton Left', 'cbleft',  1);
$df->addCheckbuttonField2('Checkbutton Right', 'cbright', 0);
$tf1 = $df->addWideTextField(undef, 'widetext', 10, 75, '');
$tf1->insert('end', 'Wide text field contents');
$lb1 = $df->addListboxField('Listbox', 'listbox', 40);
$lb1->insert('end', 'Option1');
$lb1->insert('end', 'Option 2');
$df->addHiddenField('Hidden Field', 'hidden', 123);
$e->{hidden}++;
$df->addButtonField('Invoke', 'invoke',  'i');
$df->addButtonField('Quit', 'quit',  'q', sub{$w->destroy});

ok($df->control('widetext')->Contents =~ '^Wide ', 'Control returned');

$w->MainLoop();
print Dumper $e;
