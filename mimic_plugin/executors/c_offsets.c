/* Executor B: fixed offsets, bounded byte arrays and bit-at-a-time CRC.
 * No code is generated from or linked to another executor's parser. */
#include <stdint.h>
#include <stdio.h>
#include <inttypes.h>
#include <string.h>
#ifdef _WIN32
#include <io.h>
#include <fcntl.h>
#endif

static uint64_t be(const unsigned char *p,unsigned n){uint64_t v=0;while(n--)v=(v<<8)|*p++;return v;}
static uint32_t crc32wire(const unsigned char *p,size_t n){uint32_t c=0xffffffffU;for(size_t i=0;i<n;i++){c^=p[i];for(int j=0;j<8;j++)c=(c>>1)^((c&1)?0xedb88320U:0);}return c^0xffffffffU;}
static uint32_t sum16(const unsigned char *p,size_t n){uint32_t s=0;for(size_t i=0;i<n;i+=2)s+=((uint32_t)p[i]<<8)|(i+1<n?p[i+1]:0);return s;}
static uint32_t fold(uint32_t s){while(s>>16)s=(s&65535)+(s>>16);return s;}
static void hex(const unsigned char *p,size_t n){for(size_t i=0;i<n;i++)printf("%02x",p[i]);}
static const char *names[]={"OK","WIRE_LENGTH","PREAMBLE","FCS","ETHERTYPE","IP_VERSION","IP_BOUNDS","IP_OPTIONS","IP_CHECKSUM","IP_FRAGMENT","IP_PROTOCOL","IP_TTL","UDP_LENGTH","UDP_CHECKSUM","ACL","UDP_CHECKSUM_REQUIRED"};

int main(void){
#ifdef _WIN32
 _setmode(_fileno(stdin), _O_BINARY);
 _setmode(_fileno(stdout), _O_BINARY);
#endif
 unsigned char request[4097];size_t size=fread(request,1,sizeof request,stdin);
 if(size<96||size>4096||memcmp(request,"MDH1",4))return 2;
 unsigned count=request[29],n=(unsigned)be(request+30,2);
 if(request[28]>1||count<1||count>8||n>2048||size!=96+33*count+n)return 2;
 const unsigned char *r=request+96+33*count;unsigned reason=0;int rule=-1;
 uint64_t f[9]={0};unsigned payload_start=0,payload_size=0;
 unsigned total=0,ihl=0,udp=0,check=0;uint64_t dm=0,sm=0,sip=0,dip=0,sp=0,dp=0;
 if(n<72||n>1526){reason=1;goto done;}
 {const unsigned char magic[8]={85,85,85,85,85,85,85,213};if(memcmp(r,magic,8)){reason=2;goto done;}}
 if(crc32wire(r+8,n-12)!=((uint32_t)r[n-4]|((uint32_t)r[n-3]<<8)|((uint32_t)r[n-2]<<16)|((uint32_t)r[n-1]<<24))){reason=3;goto done;}
 if(be(r+20,2)!=2048){reason=4;goto done;}
 if((r[22]>>4)!=4){reason=5;goto done;}
 ihl=(r[22]&15)*4;total=(unsigned)be(r+24,2);
 if(ihl<20||total<ihl||22+total>n-5){reason=6;goto done;}
 if(ihl!=20){reason=7;goto done;}
 if(fold(sum16(r+22,20))!=65535){reason=8;goto done;}
 if(be(r+28,2)&0xbfff){
  unsigned fragment=(unsigned)be(r+28,2);int first=(fragment&8191)==0,enabled=0;
  for(unsigned i=0;i<count;i++)if(request[96+33*i+32]&2)enabled=1;
  if(!enabled||(fragment&0x8000)||((fragment&0x4000)&&(fragment&0x3fff))||total<=20||((fragment&0x2000)&&((total-20)&7))){reason=9;goto done;}
  if(r[31]!=17){reason=10;goto done;}if(!r[30]){reason=11;goto done;}
  if(first&&total<28){reason=12;goto done;}
  dm=be(r+8,6);sm=be(r+14,6);sip=be(r+34,4);dip=be(r+38,4);sp=first?be(r+42,2):0;dp=first?be(r+44,2):0;
  for(unsigned i=0;i<count;i++){
   const unsigned char *p=request+96+33*i;
   if((p[32]&2)&&sip==be(p+2,4)&&dip==be(p+6,4)&&dm==be(p+10,8)&&((sm^be(p+18,8))&UINT64_C(0xffffffffff9f))==0&&(!first||(sp==be(p+26,2)&&dp==be(p+28,2)))&&n-8<=be(p+30,2)){
    if(first&&(p[32]&1)&&!be(r+48,2)){reason=15;goto done;}rule=(int)be(p,2);break;
   }
  }
  if(rule<0){reason=14;goto done;}
  f[0]=dm;f[1]=sm;f[2]=sip;f[3]=dip;f[4]=be(r+26,2);f[5]=r[n-5];f[6]=sp;f[7]=dp;f[8]=total+8;
  payload_start=22;payload_size=total;goto done;
 }
 if(r[31]!=17){reason=10;goto done;}
 if(!r[30]){reason=11;goto done;}
 if(total<28){reason=12;goto done;}
 sp=be(r+42,2);dp=be(r+44,2);udp=(unsigned)be(r+46,2);check=(unsigned)be(r+48,2);
 if(udp<8||udp!=total-20){reason=12;goto done;}
 if(check&&fold(sum16(r+34,8)+17+udp+sum16(r+42,udp))!=65535){reason=13;goto done;}
 dm=be(r+8,6);sm=be(r+14,6);sip=be(r+34,4);dip=be(r+38,4);
 for(unsigned i=0;i<count;i++){
  const unsigned char *p=request+96+33*i;
  if(sip==be(p+2,4)&&dip==be(p+6,4)&&dm==be(p+10,8)&&((sm^be(p+18,8))&UINT64_C(0xffffffffff9f))==0&&sp==be(p+26,2)&&dp==be(p+28,2)&&n-8<=be(p+30,2)){
   if(!check&&(p[32]&1)){reason=15;goto done;}
   rule=(int)be(p,2);break;
  }
 }
 if(rule<0){reason=14;goto done;}
 f[0]=dm;f[1]=sm;f[2]=sip;f[3]=dip;f[4]=be(r+26,2);f[5]=r[n-5];f[6]=sp;f[7]=dp;f[8]=udp;
 payload_start=50;payload_size=total-28;
done:
 printf("{\"request_id\":%" PRIu64 ",\"epoch\":%" PRIu64 ",\"generation\":%" PRIu64 ",\"policy_hash\":\"",be(request+4,8),be(request+12,4),be(request+16,4));
 hex(request+32,32);printf("\",\"input_hash\":\"");hex(request+64,32);
 printf("\",\"verdict\":\"%s\",\"reason\":\"%s\",\"rule_id\":%d,\"wire_length\":%u,\"fields\":[",reason?"deny":"allow",names[reason],reason?-1:rule,n);
 for(unsigned i=0;i<9;i++)printf("%s%" PRIu64,i?",":"",reason?UINT64_C(0):f[i]);
 printf("],\"payload_hex\":\"");if(!reason)hex(r+payload_start,payload_size);puts("\"}");
 return 0;
}
