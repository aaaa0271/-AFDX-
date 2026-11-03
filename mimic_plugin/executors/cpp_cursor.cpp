#ifdef _WIN32
#include <io.h>
#include <fcntl.h>
#endif
// Executor C: checked cursor/views, rule objects and nibble-table Ethernet CRC.
// Intentionally independent of the C offsets and Python implementations.
#include <array>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <sstream>
#include <stdexcept>
#include <vector>

struct View {
 const std::vector<unsigned char>& bytes;std::size_t begin,end;
 std::uint64_t at(std::size_t offset,std::size_t count) const {
  if(offset>end-begin||count>end-begin-offset||count>8)throw std::out_of_range("view");
  std::uint64_t value=0;for(std::size_t i=0;i<count;i++)value=value*256+bytes[begin+offset+i];return value;
 }
 View sub(std::size_t offset,std::size_t count)const {if(offset>end-begin||count>end-begin-offset)throw std::out_of_range("subview");return {bytes,begin+offset,begin+offset+count};}
 std::string hex()const {std::ostringstream out;out<<std::hex<<std::setfill('0');for(auto i=begin;i<end;i++)out<<std::setw(2)<<unsigned(bytes[i]);return out.str();}
};
struct Cursor {View v;std::size_t pos=0;std::uint64_t read(std::size_t n){auto x=v.at(pos,n);pos+=n;return x;}};
struct Rule {std::uint64_t id,sip,dip,dm,sm,sp,dp,max;unsigned require;};
static unsigned sum(const View& v){unsigned value=0;for(std::size_t i=0;i<v.end-v.begin;i+=2)value+=unsigned(v.at(i,1)<<8)|(i+1<v.end-v.begin?unsigned(v.at(i+1,1)):0);return value;}
static unsigned fold(unsigned n){for(;n>65535;n=(n&65535)+(n>>16)){}return n;}
static std::uint32_t crc(const View& v){
 constexpr std::array<std::uint32_t,16> table={0x00000000,0x1db71064,0x3b6e20c8,0x26d930ac,0x76dc4190,0x6b6b51f4,0x4db26158,0x5005713c,0xedb88320,0xf00f9344,0xd6d6a3e8,0xcb61b38c,0x9b64c2b0,0x86d3d2d4,0xa00ae278,0xbdbdf21c};
 std::uint32_t n=0xffffffff;for(auto i=v.begin;i<v.end;i++){n^=v.bytes[i];n=(n>>4)^table[n&15];n=(n>>4)^table[n&15];}return n^0xffffffff;
}
int main(){
#ifdef _WIN32
 _setmode(_fileno(stdin), _O_BINARY);
 _setmode(_fileno(stdout), _O_BINARY);
#endif
try{
 std::vector<unsigned char> bytes;bytes.reserve(4097);char b;while(bytes.size()<4097&&std::cin.get(b))bytes.push_back(static_cast<unsigned char>(b));
 View request{bytes,0,bytes.size()};if(bytes.size()<96||bytes.size()>4096||request.at(0,4)!=0x4d444831)return 2;
 auto count=request.at(29,1),n=request.at(30,2);if(request.at(28,1)>1||count<1||count>8||n>2048||bytes.size()!=96+33*count+n)return 2;
 std::vector<Rule> rules;
 for(unsigned i=0;i<count;i++){Cursor c{request.sub(96+33*i,33)};Rule r{};r.id=c.read(2);r.sip=c.read(4);r.dip=c.read(4);r.dm=c.read(8);r.sm=c.read(8);r.sp=c.read(2);r.dp=c.read(2);r.max=c.read(2);r.require=unsigned(c.read(1));rules.push_back(r);}
 View wire=request.sub(96+33*count,n);std::array<std::uint64_t,9> fields{};int match=-1;std::string payload;
 auto evaluate=[&]()->unsigned {
  if(n<72||n>1526)return 1;
  if(wire.at(0,8)!=UINT64_C(0x55555555555555d5))return 2;
  std::uint32_t check=0;for(unsigned i=0;i<4;i++)check|=std::uint32_t(wire.at(n-4+i,1))<<(8*i);
  if(crc(wire.sub(8,n-12))!=check)return 3;
  if(wire.at(20,2)!=0x0800)return 4;
  auto version=wire.at(22,1);if(version/16!=4)return 5;
  auto ip=wire.sub(22,n-27);auto length=ip.at(2,2),ihl=(version%16)*4;
  if(ihl<20||length<ihl||length>n-27)return 6;
  if(ihl!=20)return 7;
  if(fold(sum(ip.sub(0,20)))!=65535)return 8;
  auto fragment=ip.at(6,2);
  if(fragment&0xbfff){
   bool enabled=false;for(const auto& r:rules)if(r.require&2)enabled=true;
   if(!enabled||(fragment&0x8000)||((fragment&0x4000)&&(fragment&0x3fff))||length<=20||((fragment&0x2000)&&((length-20)%8)))return 9;
   if(ip.at(9,1)!=17)return 10;
   if(ip.at(8,1)==0)return 11;
   bool first=(fragment%8192)==0;if(first&&length<28)return 12;
   auto dm=wire.at(8,6),sm=wire.at(14,6),sip=ip.at(12,4),dip=ip.at(16,4);
   auto sp=first?ip.at(20,2):0,dp=first?ip.at(22,2):0;
   for(const auto& r:rules)if((r.require&2)&&r.sip==sip&&r.dip==dip&&r.dm==dm&&((r.sm^sm)&UINT64_C(0xffffffffff9f))==0&&(!first||(r.sp==sp&&r.dp==dp))&&n-8<=r.max){
    if(first&&(r.require&1)&&ip.at(26,2)==0)return 15;
    match=int(r.id);fields={dm,sm,sip,dip,ip.at(4,2),wire.at(n-5,1),sp,dp,length+8};payload=ip.sub(0,length).hex();return 0;
   }
   return 14;
  }
  if(ip.at(9,1)!=17)return 10;
  if(ip.at(8,1)==0)return 11;
  if(length<28)return 12;
  auto udp=ip.sub(20,length-20);auto size=udp.at(4,2),udpcheck=udp.at(6,2);
  if(size<8||size!=length-20)return 12;
  if(udpcheck&&fold(sum(ip.sub(12,8))+17+unsigned(size)+sum(udp))!=65535)return 13;
  auto dm=wire.at(8,6),sm=wire.at(14,6),sip=ip.at(12,4),dip=ip.at(16,4),sp=udp.at(0,2),dp=udp.at(2,2);
  for(const auto& r:rules){
   if(r.sip==sip&&r.dip==dip&&r.dm==dm&&((r.sm^sm)&UINT64_C(0xffffffffff9f))==0&&r.sp==sp&&r.dp==dp&&n-8<=r.max){
    if(!udpcheck&&(r.require&1))return 15;
    match=int(r.id);fields={dm,sm,sip,dip,ip.at(4,2),wire.at(n-5,1),sp,dp,size};payload=udp.sub(8,size-8).hex();return 0;
   }
  }return 14;
 };
 auto reason=evaluate();const char *names[]={"OK","WIRE_LENGTH","PREAMBLE","FCS","ETHERTYPE","IP_VERSION","IP_BOUNDS","IP_OPTIONS","IP_CHECKSUM","IP_FRAGMENT","IP_PROTOCOL","IP_TTL","UDP_LENGTH","UDP_CHECKSUM","ACL","UDP_CHECKSUM_REQUIRED"};
 std::cout<<"{\"request_id\":"<<request.at(4,8)<<",\"epoch\":"<<request.at(12,4)<<",\"generation\":"<<request.at(16,4)<<",\"policy_hash\":\""<<request.sub(32,32).hex()<<"\",\"input_hash\":\""<<request.sub(64,32).hex()<<"\",\"verdict\":\""<<(reason?"deny":"allow")<<"\",\"reason\":\""<<names[reason]<<"\",\"rule_id\":"<<(reason?-1:match)<<",\"wire_length\":"<<n<<",\"fields\":[";
 for(unsigned i=0;i<9;i++){std::cout<<(i?",":"")<<(reason?0:fields[i]);}
 std::cout<<"],\"payload_hex\":\""<<(reason?"":payload)<<"\"}\n";return 0;
}catch(const std::exception&){return 2;}}
