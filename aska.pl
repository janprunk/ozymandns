#!/usr/bin/perl

$VERSION=0.1;


use Net::DNS;
use MIME::Base32 qw ( RFC );
use MIME::Base64;
use Time::HiRes qw (usleep gettimeofday tv_interval);
use Getopt::Long;
use threads;
use Thread::Queue;

my %opts;

$opts{input}= "STDIN";
GetOptions(
    "mode=s"   =>   \$opts{mode},
    "input=s" =>   \$opts{input},
    "resolver=s"=>  \$opts{resolver},
    "verbose"  =>   \$opts{verbose},
    "id=s"     =>   \$opts{id}
);
$opts{mode} = uc $opts{mode};
if($opts{mode} eq "b64_txt_stream") {
   $opts{mode} eq "b64_txt";
   $opts{stream}=1;
}

chomp $opts{id};

if(!length($opts{input})){
   my $fname=$opts{input};
   open($opts{input}, "$fname");
   undef $fname;
}
binmode $opts{input};

if($ARGV[0]) {$opts{target} = $ARGV[0];}

if(!length($opts{mode}) || !length($opts{target})){
   print STDERR << "EOD";
aska $VERSION:      DNS File/Stream Sender
Component of:  OzymanDNS          Dan Kaminsky(dan\@doxpara.com)
       Usage:  geta [-o file] [-i stream_id] -r [resolver] -m MODE TARGET
     Options:  -m [mode]       :  Transfer Mode *
               -i [input]      :  Input File (stdin)
               -r              :  Nameserver(s) to use
               --id            :  Stream Identifier
       Modes:  bit_recurse     :  Bitmasked in A Records     (ANY)(   1b/p)
               b32_cname       :  Base32'd as CNAMEs       (nomde)(~110B/p) 
               b64_txt         :  Base64'd, sent in DDNS TXT(bind)(~220B/p)
               b64_txt_stream  :  Above but w/ ring buffer  (bind)(~220B/p)               
EOD
   exit(1);
}

if($opts{mode} eq "B32_CNAME")   {b32_cname()};
if($opts{mode} eq "B64_TXT")     {b64_txt()};
if($opts{mode} eq "B64_TXT_STREAM")     {b64_txt_stream()};
if($opts{mode} eq "B32_CNAME")   {b32_cname()};


sub b32_cname{
    my $var=shift @_;
    %o = %$var;
    my $file    = $opts{input};
    my $target  = $opts{target};
    my $id      = $opts{id};
    my @ns      = split(",", $opts{resolver});

    my $res   = Net::DNS::Resolver->new;
    $res->retry(5);
    $res->retrans(1);
     
    if(length($opts{resolver})) {$res->nameservers(@ns);}

    my @ns = $res->nameserver;
    binmode $file;

    my $sum = 0;
    my $try=0;

    while(1)
    {
    	my $size, $data;
    	
    	$size = sysread($file, $data, 110);
    	# if at end of data, we put a bare 0 as the content
    	if($size == 0) {
    	   $data = "0.$sum.set.$target";
    	   $res->query("$data");
    	   exit(0);
    	}
    
    	$data = lc MIME::Base32::encode($data);
    
    	$data =~s/(.{63})/$1\./g;
    	$data =~s/\=/8/g;
    	$data =~s/\n/9/g;
    	$data = "$data.$sum.set.$target";
    	$data =~s/\.\./\./g;
    
    	while($try<3){
    	  print "hmm $data\n";
    	  my $reply = $res->query("$data");
    	  if($reply) {print "$size:   $data\n"; goto bla}
    	  else       {print "error: $data ",  $res->errorstring, "\n"; $try++;}
    	}
    	bla:
    	$sum+=$size;
    	usleep(100*1000);

    }
}

sub b64_txt {
    my $var=shift @_;
    %o = %$var;
    my $file    = $opts{input};
    my $target  = $opts{target};
    my $id      = $opts{id};
    my $stream  = $opts{stream};
    my @ns      = split(",", $opts{resolver});

    my $res   = Net::DNS::Resolver->new;
    $res->retry(5);
    $res->retrans(1);
     
    if(length($opts{resolver})) {$res->nameservers(@ns);}

    my @ns = $res->nameserver;
    binmode $file;
    
    my $sum;
        
    my $update = Net::DNS::Update->new('dyn.doxpara.com');
    $update->push(update => rr_del('dyn.doxpara.com TXT'));
    $res->send($update);
    
    my $sum = 0;
    while(1)
    {
       my $update = Net::DNS::Update->new('dyn.doxpara.com');
       $update->header->id(int(rand(65536)));
       
       my $size=sysread($file, $data, 55*2);
       my $data = encode_base64($data);
       my $size2=sysread($file, $data2, 55*2);
       my $data2 = encode_base64($data2);
       
       my $offset="";
       $stream = 0;
       if($stream){ $offset = $sum % (55*2*80);}
       else       { $offset = $sum;}
       if(length($id)) {$offset="$offset\-$id";}
       $update->push(update => rr_del("$offset.$target. TXT"));
       $update->push(update => rr_add("$offset.$target. 20 TXT \"$data\" \"$data2\""));
       $update->push(update => rr_del("latest.$target.   CNAME"));
       $update->push(update => rr_add("latest.$target. 1 CNAME $offset.$target"));
    
       $oldsum = $sum;
       $sum += ($size + $size2);
       if($oldsum == $sum) {exit 0};
       
       my $reply = $res->send($update);
       # Did it work?
       if ($reply) {
           if ($reply->header->rcode eq 'NOERROR') {
              print STDERR "Update succeeded: $sum ($mod_size)\n";
           } else {
               print STDERR 'Update failed: ', $reply->header->rcode, "\n";
               exit(1);
           }
       } else {
           print STDERR 'Update failed: ', $res->errorstring, "\n";
           exit(1);
       }
    }
}
