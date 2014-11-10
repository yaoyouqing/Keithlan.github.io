#!/usr/bin/perl -w

use strict;
use FindBin qw($Bin);

our @doc_suffix  = ("doc", "docx", "md", "pdf", "xls", "xlsx", "vsd", "txt","html","ppt");
our $url_prefix  = "https://github.com/Keithlan/Keithlan.github.io/tree/master/github_md/";

my $tree_exp;
foreach my $val (@doc_suffix) {
    if($tree_exp) {
        $tree_exp .= "|*.$val";
    } else {
        $tree_exp = "*.$val";
    }
}

sub read_line {
    my $line = $_[0];

    if($line =~ m/^(.*)\.(.*)\/([^\/]+\.[a-zA-Z]+)$/) {
        if(-f "${Bin}/$2/$3") {
            return sprintf('%s<a href="%s%s/%s" target="_self">%s</a>', $1, $url_prefix, $2, $3, $3);
        } else {
            return "$1<strong>$3</strong>";
        }
    } elsif($line =~ m/(.*)\.(.*)\/([^\/]+)$/) {
        return "$1<strong>$3</strong>";
    } else {
        return $line;
    }
}

my $readme;
open(FR, "tree -f -P '$tree_exp' |") or die $!;
while(my $line=<FR>) {
    chop($line);
    $readme .= &read_line($line, @doc_suffix, $url_prefix) . "\n";
}
close(FR);

open(FW, ">${Bin}/README.md") or die $!;
print FW "<pre>$readme</pre>";
close(FW);
