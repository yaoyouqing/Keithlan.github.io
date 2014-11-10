#!/usr/bin/perl -w

use strict;
use FindBin qw($Bin);

our @doc_suffix  = ("doc", "docx", "md", "pdf", "xls", "xlsx", "vsd", "txt","html","ppt");
our $url_prefix  = "http://gitlab.corp.anjuke.com/_dba/blog/blob/master";

my $tree_exp;
foreach my $val (@doc_suffix) {
    if($tree_exp) {
        $tree_exp .= "|*.$val";
    } else {
        $tree_exp = "*.$val";
    }
}

print $tree_exp."\n";

sub read_line {
    my $line = $_[0];
    chomp($line);
    if($line =~ m/^(.*)\.(.*)\/([^\/]+\.[a-zA-Z]+)$/) {
	print "1=$1,2=$2,3=$3\n";
        if(-f "${Bin}/$2/$3") {
            return sprintf('%s[%s](%s%s/%s)',$1,$3,$url_prefix,$2,$3);
        } else {
            return "$1$3";
        }
    } elsif($line =~ m/(.*)\.(.*)\/([^\/]+)$/) {
        return "$1$3";
    } else {
        return $line;
    }
}

my $readme;
open(FR, "tree -f -P '$tree_exp'  |") or die $!;
my $tmp = '';
while(my $line=<FR>) {
    chomp($line);
    $tmp = &read_line($line, @doc_suffix, $url_prefix);
    $tmp =~ s/ /&emsp;/g;
    $readme .= $tmp."\n\n";
}
close(FR);

#$readme =~ s/ /&emsp;/g;
open(FW, ">${Bin}/README.md") or die $!;
print FW "<pre>$readme</pre>";
close(FW);
