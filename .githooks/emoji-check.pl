#!/usr/bin/env perl
# Shared emoji detector for the .githooks hooks.
#
#   emoji-check.pl msg  <commit-msg-file>   check a commit message
#   emoji-check.pl diff                     check lines added in `git diff --cached -U0` (stdin)
#
# Why: Tk/libXft < 2.3.5 (gitk over Xpra on Ubuntu 22.04) crashes on color emoji
# glyphs, and the project style is plain text. Box drawing (U+2500), arrows
# (U+2190) and the starship prompt chevrons (U+276E/U+276F) stay allowed.
use strict;
use warnings;
use utf8;
binmode STDIN,  ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

my $EMOJI = qr/[\x{2300}-\x{23FF}\x{2600}-\x{276D}\x{2770}-\x{27BF}\x{2B00}-\x{2BFF}\x{1F000}-\x{1FAFF}\x{FE0F}]/;
my $mode  = shift // '';
my @hits;

if ($mode eq 'msg') {
    my $file = shift or die "usage: $0 msg <file>\n";
    open my $fh, '<:encoding(UTF-8)', $file or die "$file: $!\n";
    while (my $line = <$fh>) {
        next if $line =~ /^#/;   # git's comment lines
        push @hits, "commit message line $.: $line" if $line =~ $EMOJI;
    }
} elsif ($mode eq 'diff') {
    my ($path, $lineno) = ('?', 0);
    while (my $line = <STDIN>) {
        if    ($line =~ m{^\+\+\+ b/(.*)$})          { $path = $1; }
        elsif ($line =~ /^@@ -\S+ \+(\d+)/)          { $lineno = $1; }
        elsif ($line =~ /^\+/ && $line !~ /^\+\+\+/) {
            push @hits, "$path:$lineno: " . substr($line, 1) if $line =~ $EMOJI;
            $lineno++;
        }
    }
} else {
    die "usage: $0 msg <file> | diff\n";
}

exit 0 unless @hits;
print STDERR "Emoji found (not allowed in this repo; see AGENTS.md > Style):\n";
print STDERR "  $_" for @hits;
print STDERR "Remove them, or bypass once with: git commit --no-verify\n";
exit 1;
