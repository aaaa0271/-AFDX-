new_case(0); // unfragmented-boundaries-and-odd-checksums
expected(1,20,0);
send_frame(0,72,3,0);
repeat(4000)@(negedge clk);
expected(17,21,0);
send_frame(72,72,3,0);
repeat(4000)@(negedge clk);
expected(18,22,0);
send_frame(144,73,3,0);
repeat(4000)@(negedge clk);
expected(1471,23,0);
send_frame(217,1526,3,0);
repeat(4000)@(negedge clk);
finish_case(4);
new_case(1); // 8192-inorder-dual-network
expected(8192,31,0);
send_frame(1743,1519,3,0);
send_frame(3262,1519,3,0);
send_frame(4781,1519,3,0);
send_frame(6300,1519,3,0);
send_frame(7819,1519,3,0);
send_frame(9338,887,3,0);
finish_case(1);
new_case(2); // 8191-final-first-outoforder
expected(8191,43,0);
send_frame(10225,886,3,0);
send_frame(11111,1519,3,0);
send_frame(12630,1519,3,0);
send_frame(14149,1519,3,0);
send_frame(15668,1519,3,0);
send_frame(17187,1519,3,0);
finish_case(1);
new_case(3); // identical-overlap-not-delivered-twice
expected(8192,55,0);
send_frame(18706,1519,3,0);
send_frame(20225,1519,3,0);
send_frame(21744,1519,3,0);
send_frame(23263,1519,3,0);
send_frame(24782,1519,3,0);
send_frame(26301,1519,3,0);
send_frame(27820,887,3,0);
finish_case(1);
new_case(4); // conflicting-overlap-aborts-and-next-message-recovers
send_frame(28707,1519,3,0);
send_frame(30226,1519,3,0);
send_frame(31745,1519,3,0);
send_frame(33264,1111,3,0);
repeat(500)@(negedge clk);if(delivered!=0)fail("conflicting overlap delivered");
expected(25,71,0);
send_frame(34375,80,3,0);
finish_case(1);
if(reassembly_errors==0)fail("overlap rejection not counted");
new_case(5); // whole-message-checksum-reject-and-recover
send_frame(34455,1519,3,0);
send_frame(35974,584,3,0);
repeat(4000)@(negedge clk);if(delivered!=0)fail("bad checksum delivered");
expected(31,81,0);
send_frame(36558,86,3,0);
finish_case(1);
new_case(6); // unrelated-id-middle-fragment-does-not-poison-context
expected(4000,90,0);
send_frame(36644,1519,3,0);
send_frame(38163,1519,3,0);
send_frame(39682,1519,3,0);
send_frame(41201,1111,3,0);
finish_case(1);
if(dropped==0)fail("unrelated ID not rejected");
new_case(7); // missing-fragment-timeout-no-partial-delivery
send_frame(42312,1519,3,0);
send_frame(43831,1519,3,0);
send_frame(45350,1519,3,0);
send_frame(46869,1519,3,0);
send_frame(48388,887,3,0);
repeat(25000)@(negedge clk);if(delivered!=0||timeouts==0)fail("missing fragment timeout/atomicity");
expected(47,101,0);
send_frame(49275,102,3,0);
finish_case(1);
new_case(8); // incorrect-final-endpoint
send_frame(49377,1519,3,0);
send_frame(50896,575,3,0);
repeat(4000)@(negedge clk);if(delivered!=0)fail("short final delivered");
expected(51,112,0);
send_frame(51471,106,3,0);
finish_case(1);
new_case(9); // invalid-alignment-ip-source-mac-and-ports-before-integrity
send_frame(51577,72,3,0);
send_frame(51649,85,3,0);
send_frame(51734,85,3,0);
send_frame(51819,85,3,0);
send_frame(51904,85,3,0);
expected(63,113,0);
send_frame(51989,118,3,0);
finish_case(1);
if(dropped<5)fail("header admission coverage");
new_case(10); // queue-full-backpressure-stable-output
ready=0;
expected(63,120,0);
send_frame(52107,118,3,0);
repeat(1000)@(negedge clk);
expected(64,121,0);
send_frame(52225,119,3,0);
repeat(1000)@(negedge clk);
send_frame(52344,120,3,0);
repeat(1000)@(negedge clk);if(delivered!=0||overflows==0)fail("queue-full handling");ready=1;
finish_case(2);
new_case(11); // two-VL-interleaved-reassembly
expected(4000,131,0);
expected(4001,132,1);
send_frame(52464,1519,3,0);
send_frame(53983,1519,3,0);
send_frame(55502,1519,3,0);
send_frame(57021,1519,3,0);
send_frame(58540,1111,3,0);
send_frame(59651,1112,3,0);
finish_case(2);
new_case(12); // bad-A-fcs-good-B-copy
expected(1471,141,0);
send_frame(60763,1526,3,1);
finish_case(1);
if(dropped==0)fail("bad A not counted");
new_case(13); // maximum-size-check
send_frame(62289,155,3,0);
expected(1,152,0);
send_frame(62444,72,3,0);
finish_case(1);
new_case(14); // mid-reassembly-reset
send_frame(62516,1519,3,0);
repeat(40)@(negedge clk);rst=1;repeat(5)@(negedge clk);rst=0;repeat(5)@(negedge clk);
expected(37,162,0);
send_frame(64035,92,3,0);
finish_case(1);
