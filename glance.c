#include <stdio.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <time.h>


int main(int argc, char **argv)
{
	struct timeval *time;
	struct hostent *host;
	char buf[256];
	time_t when;
	struct tm *tm;

	if(!argv[1]) exit(1);
	host = gethostbyname(argv[1]);

	if(!host || !host->h_addr) exit(1);

	time = (void *)host->h_addr;
	when=time->tv_sec;
	tm = gmtime(&when);

	strftime(buf, sizeof(buf), "%c GMT", tm);

	fprintf(stdout, "%u (%s)\n", time->tv_sec, buf);
	exit(0);
}

