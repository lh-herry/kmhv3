//commit b30d9d321f06274ff88cf3db27c6b6b9f5eef40a
//Author: Zhihao Xu <ngc7331@outlook.com>
//Date:   Thu May 28 10:53:59 2026 +0800
//
//    ci(emu): better log archive (#6033)
//    
//    - print unsorted stderr.log if failed
//    - do not run 'Archive log' step if previous steps are already failed
//    - archive emu-basics stdout regardless of matrix.report
//    - rename matrix.report to matrix.report-perf to clarify this is to
//    report performance-related info (IPC and stderr)
//    
//    Signed-off-by: ngc7331 <ngc7331@outlook.com>
//diff --git a/src/main/scala/top/Configs.scala b/src/main/scala/top/Configs.scala
//index 771119e44..324483e89 100644
//--- a/src/main/scala/top/Configs.scala
//+++ b/src/main/scala/top/Configs.scala
//@@ -537,6 +537,13 @@ class DefaultConfig(n: Int = 1) extends Config(
//     ++ new BaseConfig(n)
// )
// 
//+class Kmhv3Config(n: Int = 1) extends Config(
//+  OpenLLCConfig("16MB", ways = 16, banks = 4)
//+    ++ L2CacheConfig("1MB", inclusive = true, banks = 4, tp = false)
//+    ++ WithNKBL1D(64, ways = 4)
//+    ++ new BaseConfig(n)
//+)
//+
// class CVMConfig(n: Int = 1) extends Config(
//   new CVMCompile
//     ++ new DefaultConfig(n)
//diff --git a/src/main/scala/xiangshan/backend/dispatch/Dispatch.scala b/src/main/scala/xiangshan/backend/dispatch/Dispatch.scala
//index ef8dab8af..0d5ef6882 100644
//--- a/src/main/scala/xiangshan/backend/dispatch/Dispatch.scala
//+++ b/src/main/scala/xiangshan/backend/dispatch/Dispatch.scala
//@@ -477,9 +477,18 @@ class Dispatch(implicit p: Parameters) extends XSModule with HasPerfEvents with
//       }
//     }
// 
//+    val rrStart = RegInit(0.U(log2Ceil(iqNum).W))
//+    val rrFire = fromRename.map { uop =>
//+      uop.fire && fus.map(fu => uop.bits.fuType(fu.fuType.id)).reduce(_ || _)
//+    }.reduce(_ || _)
//+    when(rrFire) {
//+      rrStart := Mux(rrStart === (iqNum - 1).U, 0.U, rrStart + 1.U)
//+    }
//+
//     val minIQSel = Wire(Vec(renameWidth, Vec(issueQueueNum, Bool()))).suggestName(s"minIQSel_$suffix")
//     for (i <- 0 until renameWidth){
//-      val minIQSel_ith = (if (enableDispatchIQBalanceOpt) IQSortUpdate(i % iqNum) else IQSort(i % iqNum))
//+      val rrIdx = (rrStart + i.U) % iqNum.U
//+      val minIQSel_ith = (if (enableDispatchIQBalanceOpt) IQSortUpdate(rrIdx) else IQSort(rrIdx))
//       for (j <- 0 until issueQueueNum){
//         minIQSel(i)(j) := false.B
//         if (iqidx.contains(j)){
//diff --git a/src/main/scala/xiangshan/backend/rename/freelist/MEFreeList.scala b/src/main/scala/xiangshan/backend/rename/freelist/MEFreeList.scala
//index 4394f0404..ba8af6348 100644
//--- a/src/main/scala/xiangshan/backend/rename/freelist/MEFreeList.scala
//+++ b/src/main/scala/xiangshan/backend/rename/freelist/MEFreeList.scala
//@@ -35,6 +35,11 @@ class MEFreeList(size: Int, commitWidth: Int)(implicit p: Parameters) extends Ba
//   val doNormalRename = io.canAllocate && io.doAllocate && !io.redirect
//   val doRename = doWalkRename || doNormalRename
//   val doCommit = io.commit.doCommit
//+  val normalAllocateCount = PopCount(io.allocateReq)
//+  val freeReqCount = PopCount(io.freeReq)
//+  val recentFreeBypassCount = Mux(doNormalRename, freeReqCount min normalAllocateCount, 0.U)
//+  val remainingAllocateCount = normalAllocateCount - recentFreeBypassCount
//+  val remainingFreeCount = freeReqCount - recentFreeBypassCount
// 
//   val freeListVec = Wire(Vec(size, Vec(RenameWidth, UInt(PhyRegIdxWidth.W))))
//   for (i <- 0 until size) {
//@@ -53,7 +58,17 @@ class MEFreeList(size: Int, commitWidth: Int)(implicit p: Parameters) extends Ba
//   val phyRegCandidates = Mux1H(headPtrOHVec(0), freeListVec)
//   for (i <- 0 until RenameWidth) {
//     // enqueue instr, is move elimination
//-    io.allocatePhyReg(i) := phyRegCandidates(PopCount(io.allocateReq.take(i)))
//+    val allocIdx = PopCount(io.allocateReq.take(i))
//+    val recentFreeCandidates = VecInit((0 until commitWidth).map { j =>
//+      Mux1H(io.freeReq.zip(io.freePhyReg).zipWithIndex.map { case ((req, preg), idx) =>
//+        (req && PopCount(io.freeReq.take(idx)) === allocIdx) -> preg
//+      })
//+    })
//+    io.allocatePhyReg(i) := Mux(
//+      allocIdx < recentFreeBypassCount,
//+      recentFreeCandidates(allocIdx),
//+      phyRegCandidates(allocIdx - recentFreeBypassCount)
//+    )
//   }
//   // update arch head pointer
//   val archAlloc = io.commit.archAlloc
//@@ -64,7 +79,7 @@ class MEFreeList(size: Int, commitWidth: Int)(implicit p: Parameters) extends Ba
//   archHeadPtr := archHeadPtrNext
// 
//   // update head pointer
//-  val numAllocate = Mux(io.walk, PopCount(io.walkReq), PopCount(io.allocateReq))
//+  val numAllocate = Mux(io.walk, PopCount(io.walkReq), remainingAllocateCount)
//   val headPtrNew   = Mux(lastCycleRedirect, redirectedHeadPtr, headPtr + numAllocate)
//   val headPtrOHNew = Mux(lastCycleRedirect, redirectedHeadPtrOH, headPtrOHVec(numAllocate))
//   val headPtrNext   = Mux(doRename, headPtrNew, headPtr)
//@@ -75,10 +90,11 @@ class MEFreeList(size: Int, commitWidth: Int)(implicit p: Parameters) extends Ba
//   /**
//     * Deallocation: when refCounter becomes zero, the register can be released to freelist
//     */
//-  val freePtr = VecInit(Seq.tabulate(commitWidth)(i => tailPtr + PopCount(io.freeReq.take(i))))
//+  val freePtr = VecInit(Seq.tabulate(commitWidth)(i => tailPtr + i.U))
//   for (i <- 0 until size) {
//     val freeReqOH = VecInit(io.freeReq.zipWithIndex.map { case (w, idx) =>
//-      w && freePtr(idx).value === i.U
//+      val freeIdx = PopCount(io.freeReq.take(idx))
//+      w && freeIdx >= recentFreeBypassCount && freePtr((freeIdx - recentFreeBypassCount).asUInt).value === i.U
//     })
//     val freePhyReg = Mux1H(freeReqOH, io.freePhyReg)
//     when(freeReqOH.asUInt.orR) {
//@@ -87,14 +103,14 @@ class MEFreeList(size: Int, commitWidth: Int)(implicit p: Parameters) extends Ba
//   }
// 
//   // update tail pointer
//-  val tailPtrNext = tailPtr + PopCount(io.freeReq)
//+  val tailPtrNext = tailPtr + remainingFreeCount
//   tailPtr := tailPtrNext
// 
//   val freeRegCnt = Mux(doWalkRename && !lastCycleRedirect, distanceBetween(tailPtrNext, headPtr) - PopCount(io.walkReq),
//-                   Mux(doNormalRename,                     distanceBetween(tailPtrNext, headPtr) - PopCount(io.allocateReq),
//+                   Mux(doNormalRename,                     distanceBetween(tailPtrNext, headPtr) - remainingAllocateCount,
//                                                            distanceBetween(tailPtrNext, headPtr)))
//   val freeRegCntReg = RegNext(freeRegCnt)
//-  io.canAllocate := freeRegCntReg >= RenameWidth.U
//+  io.canAllocate := freeRegCntReg +& freeReqCount >= normalAllocateCount
// 
//   if(backendParams.debugEn){
//     val debugArchHeadPtr = RegNext(RegNext(archHeadPtr, FreeListPtr(false, 0)), FreeListPtr(false, 0)) // two-cycle delay from refCounter
//diff --git a/src/main/scala/xiangshan/backend/rename/freelist/StdFreeList.scala b/src/main/scala/xiangshan/backend/rename/freelist/StdFreeList.scala
//index e7686e6a4..e8b14d542 100644
//--- a/src/main/scala/xiangshan/backend/rename/freelist/StdFreeList.scala
//+++ b/src/main/scala/xiangshan/backend/rename/freelist/StdFreeList.scala
//@@ -36,14 +36,20 @@ class StdFreeList(
//   val freeList = RegInit(VecInit(Seq.tabulate(freeListSize)( i => (i + numLogicRegs).U(PhyRegIdxWidth.W) )))
//   val tailPtr = RegInit(FreeListPtr(true, 0)) // tailPtr in the last cycle (need to add freeReqReg)
//   val tailPtrNext = Wire(new FreeListPtr) // this is the real tailPtr
//+  val normalAllocateCount = PopCount(io.allocateReq)
//+  val freeReqCount = PopCount(io.freeReq)
//+  val recentFreeBypassCount = Wire(UInt(log2Ceil(RenameWidth + 1).W))
//+  val remainingAllocateCount = normalAllocateCount - recentFreeBypassCount
//+  val remainingFreeCount = freeReqCount - recentFreeBypassCount
// 
//   //
//   // free committed instructions' `old_pdest` reg
//   //
//-  val freePtr = VecInit(Seq.tabulate(commitWidth)(i => tailPtr + PopCount(io.freeReq.take(i))))
//+  val freePtr = VecInit(Seq.tabulate(commitWidth)(i => tailPtr + i.U))
//   for (i <- 0 until freeListSize) {
//     val freeReqOH = VecInit(io.freeReq.zipWithIndex.map { case (w, idx) =>
//-      w && freePtr(idx).value === i.U
//+      val freeIdx = PopCount(io.freeReq.take(idx))
//+      w && freeIdx >= recentFreeBypassCount && freePtr((freeIdx - recentFreeBypassCount).asUInt).value === i.U
//     })
//     val freePhyReg = Mux1H(freeReqOH, io.freePhyReg)
//     when(freeReqOH.asUInt.orR) {
//@@ -57,14 +63,14 @@ class StdFreeList(
//     XSDebug(io.freeReq(i), p"req#$i free physical reg: ${io.freePhyReg(i)}\n")
//   }
// 
//-  tailPtrNext := tailPtr + PopCount(io.freeReq)
//+  tailPtrNext := tailPtr + remainingFreeCount
//   tailPtr := tailPtrNext
// 
//   //
//   // allocate new physical registers for instructions at rename stage
//   //
//   val freeRegCnt = Wire(UInt()) // number of free registers in free list
//-  io.canAllocate := GatedValidRegNext(freeRegCnt >= RenameWidth.U) // use RegNext for better timing
//+  io.canAllocate := GatedValidRegNext(freeRegCnt +& freeReqCount >= normalAllocateCount) // use RegNext for better timing
//   XSDebug(p"freeRegCnt: $freeRegCnt\n")
// 
//   val freeListVec = Wire(Vec(freeListSize, Vec(RenameWidth, UInt(PhyRegIdxWidth.W))))
//@@ -79,9 +85,21 @@ class StdFreeList(
//   }
// 
//   val phyRegCandidates = Mux1H(headPtrOHVec(0), freeListVec)
//+  val isNormalAlloc = io.canAllocate && io.doAllocate
//+  recentFreeBypassCount := Mux(isNormalAlloc, freeReqCount min normalAllocateCount, 0.U)
// 
//   for(i <- 0 until RenameWidth) {
//-    io.allocatePhyReg(i) := phyRegCandidates(PopCount(io.allocateReq.take(i)))
//+    val allocIdx = PopCount(io.allocateReq.take(i))
//+    val recentFreeCandidates = VecInit((0 until commitWidth).map { j =>
//+      Mux1H(io.freeReq.zip(io.freePhyReg).zipWithIndex.map { case ((req, preg), idx) =>
//+        (req && PopCount(io.freeReq.take(idx)) === allocIdx) -> preg
//+      })
//+    })
//+    io.allocatePhyReg(i) := Mux(
//+      allocIdx < recentFreeBypassCount,
//+      recentFreeCandidates(allocIdx),
//+      phyRegCandidates(allocIdx - recentFreeBypassCount)
//+    )
//     XSDebug(p"req:${io.allocateReq(i)} canAllocate:${io.canAllocate} pdest:${io.allocatePhyReg(i)}\n")
//   }
//   val doCommit = io.commit.doCommit
//@@ -92,13 +110,12 @@ class StdFreeList(
//   archHeadPtr := archHeadPtrNext
// 
//   val isWalkAlloc = io.walk && io.doAllocate
//-  val isNormalAlloc = io.canAllocate && io.doAllocate
//   val isAllocate = isWalkAlloc || isNormalAlloc
//-  val numAllocate = Mux(io.walk, PopCount(io.walkReq), PopCount(io.allocateReq))
//+  val numAllocate = Mux(io.walk, PopCount(io.walkReq), remainingAllocateCount)
//   val headPtrAllocate = Mux(lastCycleRedirect, redirectedHeadPtr, headPtr + numAllocate)
//   val headPtrOHAllocate = Mux(lastCycleRedirect, redirectedHeadPtrOH, headPtrOHVec(numAllocate))
//   freeRegCnt := Mux(isWalkAlloc && !lastCycleRedirect, distanceBetween(tailPtrNext, headPtr) - PopCount(io.walkReq),
//-                Mux(isNormalAlloc,                     distanceBetween(tailPtrNext, headPtr) - PopCount(io.allocateReq),
//+                Mux(isNormalAlloc,                     distanceBetween(tailPtrNext, headPtr) - remainingAllocateCount,
//                                                        distanceBetween(tailPtrNext, headPtr)))
// 
//   // priority: (1) exception and flushPipe; (2) walking; (3) mis-prediction; (4) normal dequeue
//diff --git a/src/main/scala/xiangshan/mem/lsqueue/NewStoreQueue.scala b/src/main/scala/xiangshan/mem/lsqueue/NewStoreQueue.scala
//index bdf99707e..fa80bacf5 100644
//--- a/src/main/scala/xiangshan/mem/lsqueue/NewStoreQueue.scala
//+++ b/src/main/scala/xiangshan/mem/lsqueue/NewStoreQueue.scala
//@@ -578,15 +578,15 @@ abstract class NewStoreQueueBase(implicit p: Parameters) extends LSQModule {
//       )
//       val s2OutMask            = ParallelLookUp(s2ByteSelectOffset, s2SelectMask) & s2LoadMaskEnd
// 
//-      val s2FullOverlap        = s2SelectDataEntry.byteStart <= s2LoadStart && s2SelectDataEntry.byteEnd >= s2LoadEnd
//       // First condition: access extends beyond the lower log2Ceil(VLEN/8) bits.
//       // Second condition: higher bits of the virtual address within the page offset are non-zero, indicating a potential cross-page access.
//       val s2Cross4KPage        = s2SelectDataEntry.byteEnd(VWordOffset) && s2SelectDataEntry.vaddr(pageOffset - 1, VWordOffset).andR && s2ForwardValid
//-      val s2SafeForward        = !s2MultiMatch || s2FullOverlap
// 
//       //TODO: only use for 128-bit align forward, should revert when other forward source support rotate forward !!!!
//       val s2FinalData          = s2OutData << (s2LoadStart * 8.U)
//       val s2FinalMask          = s2OutMask << s2LoadStart
//+      val s2FullByteCoverage   = (~s2FinalMask & s2LoadMaskEnd) === 0.U
//+      val s2SafeForward        = !s2MultiMatch || s2FullByteCoverage
// 
//       val s1Resp = io.query(i).s1Resp
//       val s2Resp = io.query(i).s2Resp
// Generated by CIRCT firtool-1.135.0
module XSTop(
  input          nmi_0_0,
  input          nmi_0_1,
  input          peripheral_awready,
  output         peripheral_awvalid,
  output [1:0]   peripheral_awid,
  output [30:0]  peripheral_awaddr,
  output [7:0]   peripheral_awlen,
  output [2:0]   peripheral_awsize,
  output [1:0]   peripheral_awburst,
  output         peripheral_awlock,
  output [3:0]   peripheral_awcache,
  output [2:0]   peripheral_awprot,
  output [3:0]   peripheral_awqos,
  input          peripheral_wready,
  output         peripheral_wvalid,
  output [63:0]  peripheral_wdata,
  output [7:0]   peripheral_wstrb,
  output         peripheral_wlast,
  output         peripheral_bready,
  input          peripheral_bvalid,
  input  [1:0]   peripheral_bid,
  input  [1:0]   peripheral_bresp,
  input          peripheral_arready,
  output         peripheral_arvalid,
  output [1:0]   peripheral_arid,
  output [30:0]  peripheral_araddr,
  output [7:0]   peripheral_arlen,
  output [2:0]   peripheral_arsize,
  output [1:0]   peripheral_arburst,
  output         peripheral_arlock,
  output [3:0]   peripheral_arcache,
  output [2:0]   peripheral_arprot,
  output [3:0]   peripheral_arqos,
  output         peripheral_rready,
  input          peripheral_rvalid,
  input  [1:0]   peripheral_rid,
  input  [63:0]  peripheral_rdata,
  input  [1:0]   peripheral_rresp,
  input          peripheral_rlast,
  input          memory_awready,
  output         memory_awvalid,
  output [13:0]  memory_awid,
  output [47:0]  memory_awaddr,
  output [7:0]   memory_awlen,
  output [2:0]   memory_awsize,
  output [1:0]   memory_awburst,
  output         memory_awlock,
  output [3:0]   memory_awcache,
  output [2:0]   memory_awprot,
  output [3:0]   memory_awqos,
  input          memory_wready,
  output         memory_wvalid,
  output [255:0] memory_wdata,
  output [31:0]  memory_wstrb,
  output         memory_wlast,
  output         memory_bready,
  input          memory_bvalid,
  input  [13:0]  memory_bid,
  input  [1:0]   memory_bresp,
  input          memory_arready,
  output         memory_arvalid,
  output [13:0]  memory_arid,
  output [47:0]  memory_araddr,
  output [7:0]   memory_arlen,
  output [2:0]   memory_arsize,
  output [1:0]   memory_arburst,
  output         memory_arlock,
  output [3:0]   memory_arcache,
  output [2:0]   memory_arprot,
  output [3:0]   memory_arqos,
  output         memory_rready,
  input          memory_rvalid,
  input  [13:0]  memory_rid,
  input  [255:0] memory_rdata,
  input  [1:0]   memory_rresp,
  input          memory_rlast,
  input          io_clock,
  input          io_reset,
  input  [15:0]  io_sram_config,
  input  [63:0]  io_extIntrs,
  input          io_pll0_lock,
  output [31:0]  io_pll0_ctrl_0,
  output [31:0]  io_pll0_ctrl_1,
  output [31:0]  io_pll0_ctrl_2,
  output [31:0]  io_pll0_ctrl_3,
  output [31:0]  io_pll0_ctrl_4,
  output [31:0]  io_pll0_ctrl_5,
  input          io_systemjtag_jtag_TCK,
  input          io_systemjtag_jtag_TMS,
  input          io_systemjtag_jtag_TDI,
  output         io_systemjtag_jtag_TDO_data,
  output         io_systemjtag_jtag_TDO_driven,
  input          io_systemjtag_reset,
  input  [10:0]  io_systemjtag_mfr_id,
  input  [15:0]  io_systemjtag_part_number,
  input  [3:0]   io_systemjtag_version,
  output         io_debug_reset,
  input          io_rtc_clock,
  input          io_cacheable_check_req_0_valid,
  input  [47:0]  io_cacheable_check_req_0_bits_addr,
  input  [1:0]   io_cacheable_check_req_0_bits_size,
  input  [2:0]   io_cacheable_check_req_0_bits_cmd,
  input          io_cacheable_check_req_1_valid,
  input  [47:0]  io_cacheable_check_req_1_bits_addr,
  input  [1:0]   io_cacheable_check_req_1_bits_size,
  input  [2:0]   io_cacheable_check_req_1_bits_cmd,
  output         io_cacheable_check_resp_0_ld,
  output         io_cacheable_check_resp_0_st,
  output         io_cacheable_check_resp_0_instr,
  output         io_cacheable_check_resp_0_mmio,
  output         io_cacheable_check_resp_0_atomic,
  output         io_cacheable_check_resp_1_ld,
  output         io_cacheable_check_resp_1_st,
  output         io_cacheable_check_resp_1_instr,
  output         io_cacheable_check_resp_1_mmio,
  output         io_cacheable_check_resp_1_atomic,
  output         io_riscv_wfi_0,
  output         io_riscv_critical_error_0,
  input  [47:0]  io_riscv_rst_vec_0,
  input          io_traceCoreInterface_0_fromEncoder_enable,
  input          io_traceCoreInterface_0_fromEncoder_stall,
  output [63:0]  io_traceCoreInterface_0_toEncoder_cause,
  output [49:0]  io_traceCoreInterface_0_toEncoder_tval,
  output [2:0]   io_traceCoreInterface_0_toEncoder_priv,
  output [63:0]  io_traceCoreInterface_0_toEncoder_mstatus,
  output [2:0]   io_traceCoreInterface_0_toEncoder_valid,
  output [149:0] io_traceCoreInterface_0_toEncoder_iaddr,
  output [11:0]  io_traceCoreInterface_0_toEncoder_itype,
  output [23:0]  io_traceCoreInterface_0_toEncoder_iretire,
  output [2:0]   io_traceCoreInterface_0_toEncoder_ilastsize
);

  wire         outer_1_tx_dat_valid;
  wire         outer_1_tx_rsp_valid;
  wire         outer_1_tx_req_valid;
  wire         outer_0_tx_dat_valid;
  wire         outer_0_tx_rsp_valid;
  wire         outer_0_tx_req_valid;
  wire         _resetGen_1_o_reset;
  wire         _resetGen_o_reset;
  wire         _memLogger_io_up_rxsactive;
  wire         _memLogger_io_up_tx_linkactiveack;
  wire         _memLogger_io_up_tx_req_lcrdv;
  wire         _memLogger_io_up_tx_dat_lcrdv;
  wire         _memLogger_io_up_rx_linkactivereq;
  wire         _memLogger_io_up_rx_rsp_flitpend;
  wire         _memLogger_io_up_rx_rsp_flitv;
  wire [72:0]  _memLogger_io_up_rx_rsp_flit;
  wire         _memLogger_io_up_rx_dat_flitpend;
  wire         _memLogger_io_up_rx_dat_flitv;
  wire [421:0] _memLogger_io_up_rx_dat_flit;
  wire         _memLogger_io_down_txsactive;
  wire         _memLogger_io_down_tx_linkactivereq;
  wire         _memLogger_io_down_tx_req_flitpend;
  wire         _memLogger_io_down_tx_req_flitv;
  wire [161:0] _memLogger_io_down_tx_req_flit;
  wire         _memLogger_io_down_tx_dat_flitpend;
  wire         _memLogger_io_down_tx_dat_flitv;
  wire [421:0] _memLogger_io_down_tx_dat_flit;
  wire         _memLogger_io_down_rx_linkactiveack;
  wire         _memLogger_io_down_rx_rsp_lcrdv;
  wire         _memLogger_io_down_rx_dat_lcrdv;
  wire         _linkMonitor_2_io_in_tx_req_ready;
  wire         _linkMonitor_2_io_in_tx_rsp_ready;
  wire         _linkMonitor_2_io_in_tx_dat_ready;
  wire         _linkMonitor_2_io_in_rx_rsp_valid;
  wire [3:0]   _linkMonitor_2_io_in_rx_rsp_bits_qos;
  wire [10:0]  _linkMonitor_2_io_in_rx_rsp_bits_tgtID;
  wire [10:0]  _linkMonitor_2_io_in_rx_rsp_bits_srcID;
  wire [11:0]  _linkMonitor_2_io_in_rx_rsp_bits_txnID;
  wire [4:0]   _linkMonitor_2_io_in_rx_rsp_bits_opcode;
  wire [1:0]   _linkMonitor_2_io_in_rx_rsp_bits_respErr;
  wire [2:0]   _linkMonitor_2_io_in_rx_rsp_bits_resp;
  wire [2:0]   _linkMonitor_2_io_in_rx_rsp_bits_fwdState;
  wire [2:0]   _linkMonitor_2_io_in_rx_rsp_bits_cBusy;
  wire [11:0]  _linkMonitor_2_io_in_rx_rsp_bits_dbID;
  wire [3:0]   _linkMonitor_2_io_in_rx_rsp_bits_pCrdType;
  wire [1:0]   _linkMonitor_2_io_in_rx_rsp_bits_tagOp;
  wire         _linkMonitor_2_io_in_rx_rsp_bits_traceTag;
  wire         _linkMonitor_2_io_in_rx_dat_valid;
  wire [3:0]   _linkMonitor_2_io_in_rx_dat_bits_qos;
  wire [10:0]  _linkMonitor_2_io_in_rx_dat_bits_tgtID;
  wire [10:0]  _linkMonitor_2_io_in_rx_dat_bits_srcID;
  wire [11:0]  _linkMonitor_2_io_in_rx_dat_bits_txnID;
  wire [10:0]  _linkMonitor_2_io_in_rx_dat_bits_homeNID;
  wire [3:0]   _linkMonitor_2_io_in_rx_dat_bits_opcode;
  wire [1:0]   _linkMonitor_2_io_in_rx_dat_bits_respErr;
  wire [2:0]   _linkMonitor_2_io_in_rx_dat_bits_resp;
  wire [3:0]   _linkMonitor_2_io_in_rx_dat_bits_dataSource;
  wire [2:0]   _linkMonitor_2_io_in_rx_dat_bits_cBusy;
  wire [11:0]  _linkMonitor_2_io_in_rx_dat_bits_dbID;
  wire [1:0]   _linkMonitor_2_io_in_rx_dat_bits_ccID;
  wire [1:0]   _linkMonitor_2_io_in_rx_dat_bits_dataID;
  wire [1:0]   _linkMonitor_2_io_in_rx_dat_bits_tagOp;
  wire [7:0]   _linkMonitor_2_io_in_rx_dat_bits_tag;
  wire [1:0]   _linkMonitor_2_io_in_rx_dat_bits_tu;
  wire         _linkMonitor_2_io_in_rx_dat_bits_traceTag;
  wire [3:0]   _linkMonitor_2_io_in_rx_dat_bits_rsvdc;
  wire [31:0]  _linkMonitor_2_io_in_rx_dat_bits_be;
  wire [255:0] _linkMonitor_2_io_in_rx_dat_bits_data;
  wire [31:0]  _linkMonitor_2_io_in_rx_dat_bits_dataCheck;
  wire [3:0]   _linkMonitor_2_io_in_rx_dat_bits_poison;
  wire         _linkMonitor_2_io_in_rx_snp_valid;
  wire [3:0]   _linkMonitor_2_io_in_rx_snp_bits_qos;
  wire [10:0]  _linkMonitor_2_io_in_rx_snp_bits_srcID;
  wire [11:0]  _linkMonitor_2_io_in_rx_snp_bits_txnID;
  wire [10:0]  _linkMonitor_2_io_in_rx_snp_bits_fwdNID;
  wire [11:0]  _linkMonitor_2_io_in_rx_snp_bits_fwdTxnID;
  wire [4:0]   _linkMonitor_2_io_in_rx_snp_bits_opcode;
  wire [44:0]  _linkMonitor_2_io_in_rx_snp_bits_addr;
  wire         _linkMonitor_2_io_in_rx_snp_bits_ns;
  wire         _linkMonitor_2_io_in_rx_snp_bits_doNotGoToSD;
  wire         _linkMonitor_2_io_in_rx_snp_bits_retToSrc;
  wire         _linkMonitor_2_io_in_rx_snp_bits_traceTag;
  wire         _linkMonitor_2_io_in_rx_snp_bits_mpam_perfMonGroup;
  wire [8:0]   _linkMonitor_2_io_in_rx_snp_bits_mpam_partID;
  wire         _linkMonitor_2_io_in_rx_snp_bits_mpam_mpamNS;
  wire         _linkMonitor_2_io_out_txsactive;
  wire         _linkMonitor_2_io_out_syscoreq;
  wire         _linkMonitor_2_io_out_tx_linkactivereq;
  wire         _linkMonitor_2_io_out_tx_req_flitpend;
  wire         _linkMonitor_2_io_out_tx_req_flitv;
  wire [161:0] _linkMonitor_2_io_out_tx_req_flit;
  wire         _linkMonitor_2_io_out_tx_rsp_flitpend;
  wire         _linkMonitor_2_io_out_tx_rsp_flitv;
  wire [72:0]  _linkMonitor_2_io_out_tx_rsp_flit;
  wire         _linkMonitor_2_io_out_tx_dat_flitpend;
  wire         _linkMonitor_2_io_out_tx_dat_flitv;
  wire [421:0] _linkMonitor_2_io_out_tx_dat_flit;
  wire         _linkMonitor_2_io_out_rx_linkactiveack;
  wire         _linkMonitor_2_io_out_rx_rsp_lcrdv;
  wire         _linkMonitor_2_io_out_rx_dat_lcrdv;
  wire         _linkMonitor_2_io_out_rx_snp_lcrdv;
  wire         _linkMonitor_1_io_in_tx_req_ready;
  wire         _linkMonitor_1_io_in_tx_rsp_ready;
  wire         _linkMonitor_1_io_in_tx_dat_ready;
  wire         _linkMonitor_1_io_in_rx_rsp_valid;
  wire [3:0]   _linkMonitor_1_io_in_rx_rsp_bits_qos;
  wire [10:0]  _linkMonitor_1_io_in_rx_rsp_bits_tgtID;
  wire [10:0]  _linkMonitor_1_io_in_rx_rsp_bits_srcID;
  wire [11:0]  _linkMonitor_1_io_in_rx_rsp_bits_txnID;
  wire [4:0]   _linkMonitor_1_io_in_rx_rsp_bits_opcode;
  wire [1:0]   _linkMonitor_1_io_in_rx_rsp_bits_respErr;
  wire [2:0]   _linkMonitor_1_io_in_rx_rsp_bits_resp;
  wire [2:0]   _linkMonitor_1_io_in_rx_rsp_bits_fwdState;
  wire [2:0]   _linkMonitor_1_io_in_rx_rsp_bits_cBusy;
  wire [11:0]  _linkMonitor_1_io_in_rx_rsp_bits_dbID;
  wire [3:0]   _linkMonitor_1_io_in_rx_rsp_bits_pCrdType;
  wire [1:0]   _linkMonitor_1_io_in_rx_rsp_bits_tagOp;
  wire         _linkMonitor_1_io_in_rx_rsp_bits_traceTag;
  wire         _linkMonitor_1_io_in_rx_dat_valid;
  wire [3:0]   _linkMonitor_1_io_in_rx_dat_bits_qos;
  wire [10:0]  _linkMonitor_1_io_in_rx_dat_bits_tgtID;
  wire [10:0]  _linkMonitor_1_io_in_rx_dat_bits_srcID;
  wire [11:0]  _linkMonitor_1_io_in_rx_dat_bits_txnID;
  wire [10:0]  _linkMonitor_1_io_in_rx_dat_bits_homeNID;
  wire [3:0]   _linkMonitor_1_io_in_rx_dat_bits_opcode;
  wire [1:0]   _linkMonitor_1_io_in_rx_dat_bits_respErr;
  wire [2:0]   _linkMonitor_1_io_in_rx_dat_bits_resp;
  wire [3:0]   _linkMonitor_1_io_in_rx_dat_bits_dataSource;
  wire [2:0]   _linkMonitor_1_io_in_rx_dat_bits_cBusy;
  wire [11:0]  _linkMonitor_1_io_in_rx_dat_bits_dbID;
  wire [1:0]   _linkMonitor_1_io_in_rx_dat_bits_ccID;
  wire [1:0]   _linkMonitor_1_io_in_rx_dat_bits_dataID;
  wire [1:0]   _linkMonitor_1_io_in_rx_dat_bits_tagOp;
  wire [7:0]   _linkMonitor_1_io_in_rx_dat_bits_tag;
  wire [1:0]   _linkMonitor_1_io_in_rx_dat_bits_tu;
  wire         _linkMonitor_1_io_in_rx_dat_bits_traceTag;
  wire [3:0]   _linkMonitor_1_io_in_rx_dat_bits_rsvdc;
  wire [31:0]  _linkMonitor_1_io_in_rx_dat_bits_be;
  wire [255:0] _linkMonitor_1_io_in_rx_dat_bits_data;
  wire [31:0]  _linkMonitor_1_io_in_rx_dat_bits_dataCheck;
  wire [3:0]   _linkMonitor_1_io_in_rx_dat_bits_poison;
  wire         _linkMonitor_1_io_in_rx_snp_valid;
  wire [3:0]   _linkMonitor_1_io_in_rx_snp_bits_qos;
  wire [10:0]  _linkMonitor_1_io_in_rx_snp_bits_srcID;
  wire [11:0]  _linkMonitor_1_io_in_rx_snp_bits_txnID;
  wire [10:0]  _linkMonitor_1_io_in_rx_snp_bits_fwdNID;
  wire [11:0]  _linkMonitor_1_io_in_rx_snp_bits_fwdTxnID;
  wire [4:0]   _linkMonitor_1_io_in_rx_snp_bits_opcode;
  wire [44:0]  _linkMonitor_1_io_in_rx_snp_bits_addr;
  wire         _linkMonitor_1_io_in_rx_snp_bits_ns;
  wire         _linkMonitor_1_io_in_rx_snp_bits_doNotGoToSD;
  wire         _linkMonitor_1_io_in_rx_snp_bits_retToSrc;
  wire         _linkMonitor_1_io_in_rx_snp_bits_traceTag;
  wire         _linkMonitor_1_io_in_rx_snp_bits_mpam_perfMonGroup;
  wire [8:0]   _linkMonitor_1_io_in_rx_snp_bits_mpam_partID;
  wire         _linkMonitor_1_io_in_rx_snp_bits_mpam_mpamNS;
  wire         _linkMonitor_1_io_out_txsactive;
  wire         _linkMonitor_1_io_out_syscoreq;
  wire         _linkMonitor_1_io_out_tx_linkactivereq;
  wire         _linkMonitor_1_io_out_tx_req_flitpend;
  wire         _linkMonitor_1_io_out_tx_req_flitv;
  wire [161:0] _linkMonitor_1_io_out_tx_req_flit;
  wire         _linkMonitor_1_io_out_tx_rsp_flitpend;
  wire         _linkMonitor_1_io_out_tx_rsp_flitv;
  wire [72:0]  _linkMonitor_1_io_out_tx_rsp_flit;
  wire         _linkMonitor_1_io_out_tx_dat_flitpend;
  wire         _linkMonitor_1_io_out_tx_dat_flitv;
  wire [421:0] _linkMonitor_1_io_out_tx_dat_flit;
  wire         _linkMonitor_1_io_out_rx_linkactiveack;
  wire         _linkMonitor_1_io_out_rx_rsp_lcrdv;
  wire         _linkMonitor_1_io_out_rx_dat_lcrdv;
  wire         _linkMonitor_1_io_out_rx_snp_lcrdv;
  wire         _rxdatArb_io_out_valid;
  wire [3:0]   _rxdatArb_io_out_bits_qos;
  wire [10:0]  _rxdatArb_io_out_bits_tgtID;
  wire [10:0]  _rxdatArb_io_out_bits_srcID;
  wire [11:0]  _rxdatArb_io_out_bits_txnID;
  wire [10:0]  _rxdatArb_io_out_bits_homeNID;
  wire [3:0]   _rxdatArb_io_out_bits_opcode;
  wire [1:0]   _rxdatArb_io_out_bits_respErr;
  wire [2:0]   _rxdatArb_io_out_bits_resp;
  wire [3:0]   _rxdatArb_io_out_bits_dataSource;
  wire [2:0]   _rxdatArb_io_out_bits_cBusy;
  wire [11:0]  _rxdatArb_io_out_bits_dbID;
  wire [1:0]   _rxdatArb_io_out_bits_ccID;
  wire [1:0]   _rxdatArb_io_out_bits_dataID;
  wire [1:0]   _rxdatArb_io_out_bits_tagOp;
  wire [7:0]   _rxdatArb_io_out_bits_tag;
  wire [1:0]   _rxdatArb_io_out_bits_tu;
  wire         _rxdatArb_io_out_bits_traceTag;
  wire [3:0]   _rxdatArb_io_out_bits_rsvdc;
  wire [31:0]  _rxdatArb_io_out_bits_be;
  wire [255:0] _rxdatArb_io_out_bits_data;
  wire [31:0]  _rxdatArb_io_out_bits_dataCheck;
  wire [3:0]   _rxdatArb_io_out_bits_poison;
  wire         _rxdatArb_io_chosen;
  wire         _rxrspArb_io_out_valid;
  wire [3:0]   _rxrspArb_io_out_bits_qos;
  wire [10:0]  _rxrspArb_io_out_bits_tgtID;
  wire [10:0]  _rxrspArb_io_out_bits_srcID;
  wire [11:0]  _rxrspArb_io_out_bits_txnID;
  wire [4:0]   _rxrspArb_io_out_bits_opcode;
  wire [1:0]   _rxrspArb_io_out_bits_respErr;
  wire [2:0]   _rxrspArb_io_out_bits_resp;
  wire [2:0]   _rxrspArb_io_out_bits_fwdState;
  wire [2:0]   _rxrspArb_io_out_bits_cBusy;
  wire [11:0]  _rxrspArb_io_out_bits_dbID;
  wire [3:0]   _rxrspArb_io_out_bits_pCrdType;
  wire [1:0]   _rxrspArb_io_out_bits_tagOp;
  wire         _rxrspArb_io_out_bits_traceTag;
  wire         _rxrspArb_io_chosen;
  wire         _rxsnpArb_io_out_valid;
  wire [3:0]   _rxsnpArb_io_out_bits_qos;
  wire [10:0]  _rxsnpArb_io_out_bits_srcID;
  wire [11:0]  _rxsnpArb_io_out_bits_txnID;
  wire [10:0]  _rxsnpArb_io_out_bits_fwdNID;
  wire [11:0]  _rxsnpArb_io_out_bits_fwdTxnID;
  wire [4:0]   _rxsnpArb_io_out_bits_opcode;
  wire [44:0]  _rxsnpArb_io_out_bits_addr;
  wire         _rxsnpArb_io_out_bits_ns;
  wire         _rxsnpArb_io_out_bits_doNotGoToSD;
  wire         _rxsnpArb_io_out_bits_retToSrc;
  wire         _rxsnpArb_io_out_bits_traceTag;
  wire         _rxsnpArb_io_out_bits_mpam_perfMonGroup;
  wire [8:0]   _rxsnpArb_io_out_bits_mpam_partID;
  wire         _rxsnpArb_io_out_bits_mpam_mpamNS;
  wire         _rxsnpArb_io_chosen;
  wire         _linkMonitor_io_in_rxsactive;
  wire         _linkMonitor_io_in_syscoack;
  wire         _linkMonitor_io_in_tx_linkactiveack;
  wire         _linkMonitor_io_in_tx_req_lcrdv;
  wire         _linkMonitor_io_in_tx_rsp_lcrdv;
  wire         _linkMonitor_io_in_tx_dat_lcrdv;
  wire         _linkMonitor_io_in_rx_linkactivereq;
  wire         _linkMonitor_io_in_rx_rsp_flitpend;
  wire         _linkMonitor_io_in_rx_rsp_flitv;
  wire [72:0]  _linkMonitor_io_in_rx_rsp_flit;
  wire         _linkMonitor_io_in_rx_dat_flitpend;
  wire         _linkMonitor_io_in_rx_dat_flitv;
  wire [421:0] _linkMonitor_io_in_rx_dat_flit;
  wire         _linkMonitor_io_in_rx_snp_flitpend;
  wire         _linkMonitor_io_in_rx_snp_flitv;
  wire [114:0] _linkMonitor_io_in_rx_snp_flit;
  wire         _linkMonitor_io_out_tx_req_valid;
  wire [3:0]   _linkMonitor_io_out_tx_req_bits_qos;
  wire [10:0]  _linkMonitor_io_out_tx_req_bits_srcID;
  wire [11:0]  _linkMonitor_io_out_tx_req_bits_txnID;
  wire [10:0]  _linkMonitor_io_out_tx_req_bits_returnNID;
  wire         _linkMonitor_io_out_tx_req_bits_stashNIDValid;
  wire [11:0]  _linkMonitor_io_out_tx_req_bits_returnTxnID;
  wire [6:0]   _linkMonitor_io_out_tx_req_bits_opcode;
  wire [2:0]   _linkMonitor_io_out_tx_req_bits_size;
  wire [47:0]  _linkMonitor_io_out_tx_req_bits_addr;
  wire         _linkMonitor_io_out_tx_req_bits_ns;
  wire         _linkMonitor_io_out_tx_req_bits_likelyshared;
  wire         _linkMonitor_io_out_tx_req_bits_allowRetry;
  wire [1:0]   _linkMonitor_io_out_tx_req_bits_order;
  wire [3:0]   _linkMonitor_io_out_tx_req_bits_pCrdType;
  wire         _linkMonitor_io_out_tx_req_bits_memAttr_allocate;
  wire         _linkMonitor_io_out_tx_req_bits_memAttr_cacheable;
  wire         _linkMonitor_io_out_tx_req_bits_memAttr_device;
  wire         _linkMonitor_io_out_tx_req_bits_memAttr_ewa;
  wire         _linkMonitor_io_out_tx_req_bits_snpAttr;
  wire [7:0]   _linkMonitor_io_out_tx_req_bits_lpIDWithPadding;
  wire         _linkMonitor_io_out_tx_req_bits_snoopMe;
  wire         _linkMonitor_io_out_tx_req_bits_expCompAck;
  wire [1:0]   _linkMonitor_io_out_tx_req_bits_tagOp;
  wire         _linkMonitor_io_out_tx_req_bits_traceTag;
  wire         _linkMonitor_io_out_tx_req_bits_mpam_perfMonGroup;
  wire [8:0]   _linkMonitor_io_out_tx_req_bits_mpam_partID;
  wire         _linkMonitor_io_out_tx_req_bits_mpam_mpamNS;
  wire [3:0]   _linkMonitor_io_out_tx_req_bits_rsvdc;
  wire         _linkMonitor_io_out_tx_rsp_valid;
  wire [3:0]   _linkMonitor_io_out_tx_rsp_bits_qos;
  wire [10:0]  _linkMonitor_io_out_tx_rsp_bits_tgtID;
  wire [10:0]  _linkMonitor_io_out_tx_rsp_bits_srcID;
  wire [11:0]  _linkMonitor_io_out_tx_rsp_bits_txnID;
  wire [4:0]   _linkMonitor_io_out_tx_rsp_bits_opcode;
  wire [1:0]   _linkMonitor_io_out_tx_rsp_bits_respErr;
  wire [2:0]   _linkMonitor_io_out_tx_rsp_bits_resp;
  wire [2:0]   _linkMonitor_io_out_tx_rsp_bits_fwdState;
  wire [2:0]   _linkMonitor_io_out_tx_rsp_bits_cBusy;
  wire [11:0]  _linkMonitor_io_out_tx_rsp_bits_dbID;
  wire [3:0]   _linkMonitor_io_out_tx_rsp_bits_pCrdType;
  wire [1:0]   _linkMonitor_io_out_tx_rsp_bits_tagOp;
  wire         _linkMonitor_io_out_tx_rsp_bits_traceTag;
  wire         _linkMonitor_io_out_tx_dat_valid;
  wire [3:0]   _linkMonitor_io_out_tx_dat_bits_qos;
  wire [10:0]  _linkMonitor_io_out_tx_dat_bits_tgtID;
  wire [10:0]  _linkMonitor_io_out_tx_dat_bits_srcID;
  wire [11:0]  _linkMonitor_io_out_tx_dat_bits_txnID;
  wire [10:0]  _linkMonitor_io_out_tx_dat_bits_homeNID;
  wire [3:0]   _linkMonitor_io_out_tx_dat_bits_opcode;
  wire [1:0]   _linkMonitor_io_out_tx_dat_bits_respErr;
  wire [2:0]   _linkMonitor_io_out_tx_dat_bits_resp;
  wire [3:0]   _linkMonitor_io_out_tx_dat_bits_dataSource;
  wire [2:0]   _linkMonitor_io_out_tx_dat_bits_cBusy;
  wire [11:0]  _linkMonitor_io_out_tx_dat_bits_dbID;
  wire [1:0]   _linkMonitor_io_out_tx_dat_bits_ccID;
  wire [1:0]   _linkMonitor_io_out_tx_dat_bits_dataID;
  wire [1:0]   _linkMonitor_io_out_tx_dat_bits_tagOp;
  wire [7:0]   _linkMonitor_io_out_tx_dat_bits_tag;
  wire [1:0]   _linkMonitor_io_out_tx_dat_bits_tu;
  wire         _linkMonitor_io_out_tx_dat_bits_traceTag;
  wire [3:0]   _linkMonitor_io_out_tx_dat_bits_rsvdc;
  wire [31:0]  _linkMonitor_io_out_tx_dat_bits_be;
  wire [255:0] _linkMonitor_io_out_tx_dat_bits_data;
  wire [31:0]  _linkMonitor_io_out_tx_dat_bits_dataCheck;
  wire [3:0]   _linkMonitor_io_out_tx_dat_bits_poison;
  wire         _linkMonitor_io_out_rx_rsp_ready;
  wire         _linkMonitor_io_out_rx_dat_ready;
  wire         _linkMonitor_io_out_rx_snp_ready;
  wire         _llcLogger_io_up_rxsactive;
  wire         _llcLogger_io_up_syscoack;
  wire         _llcLogger_io_up_tx_linkactiveack;
  wire         _llcLogger_io_up_tx_req_lcrdv;
  wire         _llcLogger_io_up_tx_rsp_lcrdv;
  wire         _llcLogger_io_up_tx_dat_lcrdv;
  wire         _llcLogger_io_up_rx_linkactivereq;
  wire         _llcLogger_io_up_rx_rsp_flitpend;
  wire         _llcLogger_io_up_rx_rsp_flitv;
  wire [72:0]  _llcLogger_io_up_rx_rsp_flit;
  wire         _llcLogger_io_up_rx_dat_flitpend;
  wire         _llcLogger_io_up_rx_dat_flitv;
  wire [421:0] _llcLogger_io_up_rx_dat_flit;
  wire         _llcLogger_io_up_rx_snp_flitpend;
  wire         _llcLogger_io_up_rx_snp_flitv;
  wire [114:0] _llcLogger_io_up_rx_snp_flit;
  wire         _llcLogger_io_down_txsactive;
  wire         _llcLogger_io_down_syscoreq;
  wire         _llcLogger_io_down_tx_linkactivereq;
  wire         _llcLogger_io_down_tx_req_flitpend;
  wire         _llcLogger_io_down_tx_req_flitv;
  wire [161:0] _llcLogger_io_down_tx_req_flit;
  wire         _llcLogger_io_down_tx_rsp_flitpend;
  wire         _llcLogger_io_down_tx_rsp_flitv;
  wire [72:0]  _llcLogger_io_down_tx_rsp_flit;
  wire         _llcLogger_io_down_tx_dat_flitpend;
  wire         _llcLogger_io_down_tx_dat_flitv;
  wire [421:0] _llcLogger_io_down_tx_dat_flit;
  wire         _llcLogger_io_down_rx_linkactiveack;
  wire         _llcLogger_io_down_rx_rsp_lcrdv;
  wire         _llcLogger_io_down_rx_dat_lcrdv;
  wire         _llcLogger_io_down_rx_snp_lcrdv;
  wire         _mmioLogger_io_up_rxsactive;
  wire         _mmioLogger_io_up_syscoack;
  wire         _mmioLogger_io_up_tx_linkactiveack;
  wire         _mmioLogger_io_up_tx_req_lcrdv;
  wire         _mmioLogger_io_up_tx_rsp_lcrdv;
  wire         _mmioLogger_io_up_tx_dat_lcrdv;
  wire         _mmioLogger_io_up_rx_linkactivereq;
  wire         _mmioLogger_io_up_rx_rsp_flitpend;
  wire         _mmioLogger_io_up_rx_rsp_flitv;
  wire [72:0]  _mmioLogger_io_up_rx_rsp_flit;
  wire         _mmioLogger_io_up_rx_dat_flitpend;
  wire         _mmioLogger_io_up_rx_dat_flitv;
  wire [421:0] _mmioLogger_io_up_rx_dat_flit;
  wire         _mmioLogger_io_up_rx_snp_flitpend;
  wire         _mmioLogger_io_up_rx_snp_flitv;
  wire [114:0] _mmioLogger_io_up_rx_snp_flit;
  wire         _mmioLogger_io_down_txsactive;
  wire         _mmioLogger_io_down_tx_linkactivereq;
  wire         _mmioLogger_io_down_tx_req_flitpend;
  wire         _mmioLogger_io_down_tx_req_flitv;
  wire [161:0] _mmioLogger_io_down_tx_req_flit;
  wire         _mmioLogger_io_down_tx_dat_flitpend;
  wire         _mmioLogger_io_down_tx_dat_flitv;
  wire [421:0] _mmioLogger_io_down_tx_dat_flit;
  wire         _mmioLogger_io_down_rx_linkactiveack;
  wire         _mmioLogger_io_down_rx_rsp_lcrdv;
  wire         _mmioLogger_io_down_rx_dat_lcrdv;
  wire         _ref_reset_sync_resetSync_o_reset;
  wire         _chi_openllc_opt_io_rn_0_rxsactive;
  wire         _chi_openllc_opt_io_rn_0_syscoack;
  wire         _chi_openllc_opt_io_rn_0_tx_linkactiveack;
  wire         _chi_openllc_opt_io_rn_0_tx_req_lcrdv;
  wire         _chi_openllc_opt_io_rn_0_tx_rsp_lcrdv;
  wire         _chi_openllc_opt_io_rn_0_tx_dat_lcrdv;
  wire         _chi_openllc_opt_io_rn_0_rx_linkactivereq;
  wire         _chi_openllc_opt_io_rn_0_rx_rsp_flitpend;
  wire         _chi_openllc_opt_io_rn_0_rx_rsp_flitv;
  wire [72:0]  _chi_openllc_opt_io_rn_0_rx_rsp_flit;
  wire         _chi_openllc_opt_io_rn_0_rx_dat_flitpend;
  wire         _chi_openllc_opt_io_rn_0_rx_dat_flitv;
  wire [421:0] _chi_openllc_opt_io_rn_0_rx_dat_flit;
  wire         _chi_openllc_opt_io_rn_0_rx_snp_flitpend;
  wire         _chi_openllc_opt_io_rn_0_rx_snp_flitv;
  wire [114:0] _chi_openllc_opt_io_rn_0_rx_snp_flit;
  wire         _chi_openllc_opt_io_sn_txsactive;
  wire         _chi_openllc_opt_io_sn_tx_linkactivereq;
  wire         _chi_openllc_opt_io_sn_tx_req_flitpend;
  wire         _chi_openllc_opt_io_sn_tx_req_flitv;
  wire [161:0] _chi_openllc_opt_io_sn_tx_req_flit;
  wire         _chi_openllc_opt_io_sn_tx_dat_flitpend;
  wire         _chi_openllc_opt_io_sn_tx_dat_flitv;
  wire [421:0] _chi_openllc_opt_io_sn_tx_dat_flit;
  wire         _chi_openllc_opt_io_sn_rx_linkactiveack;
  wire         _chi_openllc_opt_io_sn_rx_rsp_lcrdv;
  wire         _chi_openllc_opt_io_sn_rx_dat_lcrdv;
  wire         _chi_openllc_opt_io_l3Miss;
  wire         _jtag_reset_sync_resetSync_o_reset;
  wire         _reset_sync_resetSync_o_reset;
  wire         _intBuffer_auto_out_0;
  wire         _chi_mmioBridge_opt_auto_axi4_out_aw_valid;
  wire [4:0]   _chi_mmioBridge_opt_auto_axi4_out_aw_bits_id;
  wire [48:0]  _chi_mmioBridge_opt_auto_axi4_out_aw_bits_addr;
  wire [7:0]   _chi_mmioBridge_opt_auto_axi4_out_aw_bits_len;
  wire [2:0]   _chi_mmioBridge_opt_auto_axi4_out_aw_bits_size;
  wire [1:0]   _chi_mmioBridge_opt_auto_axi4_out_aw_bits_burst;
  wire [3:0]   _chi_mmioBridge_opt_auto_axi4_out_aw_bits_cache;
  wire [3:0]   _chi_mmioBridge_opt_auto_axi4_out_aw_bits_qos;
  wire         _chi_mmioBridge_opt_auto_axi4_out_w_valid;
  wire [255:0] _chi_mmioBridge_opt_auto_axi4_out_w_bits_data;
  wire [31:0]  _chi_mmioBridge_opt_auto_axi4_out_w_bits_strb;
  wire         _chi_mmioBridge_opt_auto_axi4_out_w_bits_last;
  wire         _chi_mmioBridge_opt_auto_axi4_out_ar_valid;
  wire [4:0]   _chi_mmioBridge_opt_auto_axi4_out_ar_bits_id;
  wire [48:0]  _chi_mmioBridge_opt_auto_axi4_out_ar_bits_addr;
  wire [7:0]   _chi_mmioBridge_opt_auto_axi4_out_ar_bits_len;
  wire [2:0]   _chi_mmioBridge_opt_auto_axi4_out_ar_bits_size;
  wire [1:0]   _chi_mmioBridge_opt_auto_axi4_out_ar_bits_burst;
  wire [3:0]   _chi_mmioBridge_opt_auto_axi4_out_ar_bits_cache;
  wire [3:0]   _chi_mmioBridge_opt_auto_axi4_out_ar_bits_qos;
  wire         _chi_mmioBridge_opt_io_chi_rxsactive;
  wire         _chi_mmioBridge_opt_io_chi_tx_linkactiveack;
  wire         _chi_mmioBridge_opt_io_chi_tx_req_lcrdv;
  wire         _chi_mmioBridge_opt_io_chi_tx_dat_lcrdv;
  wire         _chi_mmioBridge_opt_io_chi_rx_linkactivereq;
  wire         _chi_mmioBridge_opt_io_chi_rx_rsp_flitpend;
  wire         _chi_mmioBridge_opt_io_chi_rx_rsp_flitv;
  wire [72:0]  _chi_mmioBridge_opt_io_chi_rx_rsp_flit;
  wire         _chi_mmioBridge_opt_io_chi_rx_dat_flitpend;
  wire         _chi_mmioBridge_opt_io_chi_rx_dat_flitv;
  wire [421:0] _chi_mmioBridge_opt_io_chi_rx_dat_flit;
  wire         _chi_llcBridge_opt_auto_axi4_out_aw_valid;
  wire [5:0]   _chi_llcBridge_opt_auto_axi4_out_aw_bits_id;
  wire [48:0]  _chi_llcBridge_opt_auto_axi4_out_aw_bits_addr;
  wire [7:0]   _chi_llcBridge_opt_auto_axi4_out_aw_bits_len;
  wire [2:0]   _chi_llcBridge_opt_auto_axi4_out_aw_bits_size;
  wire [1:0]   _chi_llcBridge_opt_auto_axi4_out_aw_bits_burst;
  wire [3:0]   _chi_llcBridge_opt_auto_axi4_out_aw_bits_qos;
  wire         _chi_llcBridge_opt_auto_axi4_out_w_valid;
  wire [255:0] _chi_llcBridge_opt_auto_axi4_out_w_bits_data;
  wire [31:0]  _chi_llcBridge_opt_auto_axi4_out_w_bits_strb;
  wire         _chi_llcBridge_opt_auto_axi4_out_w_bits_last;
  wire         _chi_llcBridge_opt_auto_axi4_out_ar_valid;
  wire [5:0]   _chi_llcBridge_opt_auto_axi4_out_ar_bits_id;
  wire [48:0]  _chi_llcBridge_opt_auto_axi4_out_ar_bits_addr;
  wire [7:0]   _chi_llcBridge_opt_auto_axi4_out_ar_bits_len;
  wire [2:0]   _chi_llcBridge_opt_auto_axi4_out_ar_bits_size;
  wire [1:0]   _chi_llcBridge_opt_auto_axi4_out_ar_bits_burst;
  wire [3:0]   _chi_llcBridge_opt_auto_axi4_out_ar_bits_qos;
  wire         _chi_llcBridge_opt_io_chi_rxsactive;
  wire         _chi_llcBridge_opt_io_chi_tx_linkactiveack;
  wire         _chi_llcBridge_opt_io_chi_tx_req_lcrdv;
  wire         _chi_llcBridge_opt_io_chi_tx_dat_lcrdv;
  wire         _chi_llcBridge_opt_io_chi_rx_linkactivereq;
  wire         _chi_llcBridge_opt_io_chi_rx_rsp_flitpend;
  wire         _chi_llcBridge_opt_io_chi_rx_rsp_flitv;
  wire [72:0]  _chi_llcBridge_opt_io_chi_rx_rsp_flit;
  wire         _chi_llcBridge_opt_io_chi_rx_dat_flitpend;
  wire         _chi_llcBridge_opt_io_chi_rx_dat_flitv;
  wire [421:0] _chi_llcBridge_opt_io_chi_rx_dat_flit;
  wire         _core_with_l2_auto_l2top_inner_beu_int_out_0;
  wire         _core_with_l2_io_hartIsInReset;
  wire         _core_with_l2_io_traceCoreInterface_toEncoder_groups_0_valid;
  wire [49:0]  _core_with_l2_io_traceCoreInterface_toEncoder_groups_0_bits_iaddr;
  wire [3:0]   _core_with_l2_io_traceCoreInterface_toEncoder_groups_0_bits_itype;
  wire [7:0]   _core_with_l2_io_traceCoreInterface_toEncoder_groups_0_bits_iretire;
  wire         _core_with_l2_io_traceCoreInterface_toEncoder_groups_0_bits_ilastsize;
  wire         _core_with_l2_io_traceCoreInterface_toEncoder_groups_1_valid;
  wire [49:0]  _core_with_l2_io_traceCoreInterface_toEncoder_groups_1_bits_iaddr;
  wire [3:0]   _core_with_l2_io_traceCoreInterface_toEncoder_groups_1_bits_itype;
  wire [7:0]   _core_with_l2_io_traceCoreInterface_toEncoder_groups_1_bits_iretire;
  wire         _core_with_l2_io_traceCoreInterface_toEncoder_groups_1_bits_ilastsize;
  wire         _core_with_l2_io_traceCoreInterface_toEncoder_groups_2_valid;
  wire [49:0]  _core_with_l2_io_traceCoreInterface_toEncoder_groups_2_bits_iaddr;
  wire [3:0]   _core_with_l2_io_traceCoreInterface_toEncoder_groups_2_bits_itype;
  wire [7:0]   _core_with_l2_io_traceCoreInterface_toEncoder_groups_2_bits_iretire;
  wire         _core_with_l2_io_traceCoreInterface_toEncoder_groups_2_bits_ilastsize;
  wire         _core_with_l2_io_chi_txsactive;
  wire         _core_with_l2_io_chi_syscoreq;
  wire         _core_with_l2_io_chi_tx_linkactivereq;
  wire         _core_with_l2_io_chi_tx_req_flitpend;
  wire         _core_with_l2_io_chi_tx_req_flitv;
  wire [161:0] _core_with_l2_io_chi_tx_req_flit;
  wire         _core_with_l2_io_chi_tx_rsp_flitpend;
  wire         _core_with_l2_io_chi_tx_rsp_flitv;
  wire [72:0]  _core_with_l2_io_chi_tx_rsp_flit;
  wire         _core_with_l2_io_chi_tx_dat_flitpend;
  wire         _core_with_l2_io_chi_tx_dat_flitv;
  wire [421:0] _core_with_l2_io_chi_tx_dat_flit;
  wire         _core_with_l2_io_chi_rx_linkactiveack;
  wire         _core_with_l2_io_chi_rx_rsp_lcrdv;
  wire         _core_with_l2_io_chi_rx_dat_lcrdv;
  wire         _core_with_l2_io_chi_rx_snp_lcrdv;
  wire         _nocMisc_auto_debugModule_debug_dmOuter_dmOuter_int_out_0;
  wire         _nocMisc_auto_timer_int_out_0;
  wire         _nocMisc_auto_timer_int_out_1;
  wire         _nocMisc_auto_plic_int_out_1_0;
  wire         _nocMisc_auto_plic_int_out_0_0;
  wire         _nocMisc_auto_axi4xbar_in_1_aw_ready;
  wire         _nocMisc_auto_axi4xbar_in_1_w_ready;
  wire         _nocMisc_auto_axi4xbar_in_1_b_valid;
  wire [4:0]   _nocMisc_auto_axi4xbar_in_1_b_bits_id;
  wire         _nocMisc_auto_axi4xbar_in_1_ar_ready;
  wire         _nocMisc_auto_axi4xbar_in_1_r_valid;
  wire [4:0]   _nocMisc_auto_axi4xbar_in_1_r_bits_id;
  wire [255:0] _nocMisc_auto_axi4xbar_in_1_r_bits_data;
  wire         _nocMisc_auto_axi4xbar_in_1_r_bits_last;
  wire         _nocMisc_auto_axi4xbar_in_0_aw_ready;
  wire         _nocMisc_auto_axi4xbar_in_0_w_ready;
  wire         _nocMisc_auto_axi4xbar_in_0_b_valid;
  wire [5:0]   _nocMisc_auto_axi4xbar_in_0_b_bits_id;
  wire         _nocMisc_auto_axi4xbar_in_0_ar_ready;
  wire         _nocMisc_auto_axi4xbar_in_0_r_valid;
  wire [5:0]   _nocMisc_auto_axi4xbar_in_0_r_bits_id;
  wire [255:0] _nocMisc_auto_axi4xbar_in_0_r_bits_data;
  wire         _nocMisc_auto_axi4xbar_in_0_r_bits_last;
  wire         _nocMisc_debug_module_io_resetCtrl_hartResetReq_0;
  wire         _nocMisc_debug_module_io_debugIO_dmactive;
  wire         _nocMisc_clintTime_valid;
  wire [63:0]  _nocMisc_clintTime_bits;
  wire         _inner_tx_req_bits_tgtID_T_49 =
    _linkMonitor_io_out_tx_req_bits_addr[47:31] == 17'h0;
  wire         _inner_tx_req_bits_tgtID_T_106 =
    _inner_tx_req_bits_tgtID_T_49
    | {_linkMonitor_io_out_tx_req_bits_addr[47:40],
       ~(_linkMonitor_io_out_tx_req_bits_addr[39])} == 9'h0;
  wire [1:0]   _inner_tx_req_bits_tgtID_T_123 =
    {_linkMonitor_io_out_tx_req_bits_addr[47:35],
     ~(_linkMonitor_io_out_tx_req_bits_addr[34])} == 14'h0
    | {_linkMonitor_io_out_tx_req_bits_addr[47:37],
       ~(_linkMonitor_io_out_tx_req_bits_addr[36])} == 12'h0
    | {_linkMonitor_io_out_tx_req_bits_addr[47:39],
       ~(_linkMonitor_io_out_tx_req_bits_addr[38])} == 10'h0
    | {_linkMonitor_io_out_tx_req_bits_addr[47:43],
       ~(_linkMonitor_io_out_tx_req_bits_addr[42])} == 6'h0
    | {_linkMonitor_io_out_tx_req_bits_addr[47:33],
       ~(_linkMonitor_io_out_tx_req_bits_addr[32])} == 16'h0
    | {_linkMonitor_io_out_tx_req_bits_addr[47:44],
       ~(_linkMonitor_io_out_tx_req_bits_addr[43])} == 5'h0
    | {_linkMonitor_io_out_tx_req_bits_addr[47:38],
       ~(_linkMonitor_io_out_tx_req_bits_addr[37])} == 11'h0
    | {_linkMonitor_io_out_tx_req_bits_addr[47],
       ~(_linkMonitor_io_out_tx_req_bits_addr[46])} == 2'h0
    | {_linkMonitor_io_out_tx_req_bits_addr[47:45],
       ~(_linkMonitor_io_out_tx_req_bits_addr[44])} == 4'h0
    | ~((_inner_tx_req_bits_tgtID_T_106
         | {_linkMonitor_io_out_tx_req_bits_addr[47:34],
            ~(_linkMonitor_io_out_tx_req_bits_addr[33])} == 15'h0
         | {_linkMonitor_io_out_tx_req_bits_addr[47:46],
            ~(_linkMonitor_io_out_tx_req_bits_addr[45])} == 3'h0)
        & _inner_tx_req_bits_tgtID_T_106 & _inner_tx_req_bits_tgtID_T_49)
      ? 2'h2
      : 2'h1;
  wire [10:0]  linkMonitor_2_io_in_tx_req_bits_tgtID =
    {9'h0, _inner_tx_req_bits_tgtID_T_123};
  assign outer_0_tx_req_valid =
    _linkMonitor_io_out_tx_req_valid & _inner_tx_req_bits_tgtID_T_123 == 2'h2;
  assign outer_0_tx_rsp_valid =
    _linkMonitor_io_out_tx_rsp_valid & _linkMonitor_io_out_tx_rsp_bits_tgtID == 11'h2;
  assign outer_0_tx_dat_valid =
    _linkMonitor_io_out_tx_dat_valid & _linkMonitor_io_out_tx_dat_bits_tgtID == 11'h2;
  wire         _outer_1_rx_snp_ready_T =
    _linkMonitor_io_out_rx_snp_ready & _rxsnpArb_io_out_valid;
  wire         _outer_1_rx_rsp_ready_T =
    _linkMonitor_io_out_rx_rsp_ready & _rxrspArb_io_out_valid;
  wire         _outer_1_rx_dat_ready_T =
    _linkMonitor_io_out_rx_dat_ready & _rxdatArb_io_out_valid;
  assign outer_1_tx_req_valid =
    _linkMonitor_io_out_tx_req_valid & _inner_tx_req_bits_tgtID_T_123 == 2'h1;
  assign outer_1_tx_rsp_valid =
    _linkMonitor_io_out_tx_rsp_valid & _linkMonitor_io_out_tx_rsp_bits_tgtID == 11'h1;
  assign outer_1_tx_dat_valid =
    _linkMonitor_io_out_tx_dat_valid & _linkMonitor_io_out_tx_dat_bits_tgtID == 11'h1;
  MemMisc nocMisc (
    .clock                                              (io_clock),
    .reset                                              (_resetGen_o_reset),
    .auto_debugModule_debug_dmOuter_dmOuter_int_out_0
      (_nocMisc_auto_debugModule_debug_dmOuter_dmOuter_int_out_0),
    .auto_timer_int_out_0                               (_nocMisc_auto_timer_int_out_0),
    .auto_timer_int_out_1                               (_nocMisc_auto_timer_int_out_1),
    .auto_plic_int_in_0                                 (_intBuffer_auto_out_0),
    .auto_plic_int_out_1_0                              (_nocMisc_auto_plic_int_out_1_0),
    .auto_plic_int_out_0_0                              (_nocMisc_auto_plic_int_out_0_0),
    .auto_axi4xbar_in_1_aw_ready
      (_nocMisc_auto_axi4xbar_in_1_aw_ready),
    .auto_axi4xbar_in_1_aw_valid
      (_chi_mmioBridge_opt_auto_axi4_out_aw_valid),
    .auto_axi4xbar_in_1_aw_bits_id
      (_chi_mmioBridge_opt_auto_axi4_out_aw_bits_id),
    .auto_axi4xbar_in_1_aw_bits_addr
      (_chi_mmioBridge_opt_auto_axi4_out_aw_bits_addr),
    .auto_axi4xbar_in_1_aw_bits_len
      (_chi_mmioBridge_opt_auto_axi4_out_aw_bits_len),
    .auto_axi4xbar_in_1_aw_bits_size
      (_chi_mmioBridge_opt_auto_axi4_out_aw_bits_size),
    .auto_axi4xbar_in_1_aw_bits_burst
      (_chi_mmioBridge_opt_auto_axi4_out_aw_bits_burst),
    .auto_axi4xbar_in_1_aw_bits_cache
      (_chi_mmioBridge_opt_auto_axi4_out_aw_bits_cache),
    .auto_axi4xbar_in_1_aw_bits_qos
      (_chi_mmioBridge_opt_auto_axi4_out_aw_bits_qos),
    .auto_axi4xbar_in_1_w_ready
      (_nocMisc_auto_axi4xbar_in_1_w_ready),
    .auto_axi4xbar_in_1_w_valid
      (_chi_mmioBridge_opt_auto_axi4_out_w_valid),
    .auto_axi4xbar_in_1_w_bits_data
      (_chi_mmioBridge_opt_auto_axi4_out_w_bits_data),
    .auto_axi4xbar_in_1_w_bits_strb
      (_chi_mmioBridge_opt_auto_axi4_out_w_bits_strb),
    .auto_axi4xbar_in_1_w_bits_last
      (_chi_mmioBridge_opt_auto_axi4_out_w_bits_last),
    .auto_axi4xbar_in_1_b_valid
      (_nocMisc_auto_axi4xbar_in_1_b_valid),
    .auto_axi4xbar_in_1_b_bits_id
      (_nocMisc_auto_axi4xbar_in_1_b_bits_id),
    .auto_axi4xbar_in_1_ar_ready
      (_nocMisc_auto_axi4xbar_in_1_ar_ready),
    .auto_axi4xbar_in_1_ar_valid
      (_chi_mmioBridge_opt_auto_axi4_out_ar_valid),
    .auto_axi4xbar_in_1_ar_bits_id
      (_chi_mmioBridge_opt_auto_axi4_out_ar_bits_id),
    .auto_axi4xbar_in_1_ar_bits_addr
      (_chi_mmioBridge_opt_auto_axi4_out_ar_bits_addr),
    .auto_axi4xbar_in_1_ar_bits_len
      (_chi_mmioBridge_opt_auto_axi4_out_ar_bits_len),
    .auto_axi4xbar_in_1_ar_bits_size
      (_chi_mmioBridge_opt_auto_axi4_out_ar_bits_size),
    .auto_axi4xbar_in_1_ar_bits_burst
      (_chi_mmioBridge_opt_auto_axi4_out_ar_bits_burst),
    .auto_axi4xbar_in_1_ar_bits_cache
      (_chi_mmioBridge_opt_auto_axi4_out_ar_bits_cache),
    .auto_axi4xbar_in_1_ar_bits_qos
      (_chi_mmioBridge_opt_auto_axi4_out_ar_bits_qos),
    .auto_axi4xbar_in_1_r_valid
      (_nocMisc_auto_axi4xbar_in_1_r_valid),
    .auto_axi4xbar_in_1_r_bits_id
      (_nocMisc_auto_axi4xbar_in_1_r_bits_id),
    .auto_axi4xbar_in_1_r_bits_data
      (_nocMisc_auto_axi4xbar_in_1_r_bits_data),
    .auto_axi4xbar_in_1_r_bits_last
      (_nocMisc_auto_axi4xbar_in_1_r_bits_last),
    .auto_axi4xbar_in_0_aw_ready
      (_nocMisc_auto_axi4xbar_in_0_aw_ready),
    .auto_axi4xbar_in_0_aw_valid
      (_chi_llcBridge_opt_auto_axi4_out_aw_valid),
    .auto_axi4xbar_in_0_aw_bits_id
      (_chi_llcBridge_opt_auto_axi4_out_aw_bits_id),
    .auto_axi4xbar_in_0_aw_bits_addr
      (_chi_llcBridge_opt_auto_axi4_out_aw_bits_addr),
    .auto_axi4xbar_in_0_aw_bits_len
      (_chi_llcBridge_opt_auto_axi4_out_aw_bits_len),
    .auto_axi4xbar_in_0_aw_bits_size
      (_chi_llcBridge_opt_auto_axi4_out_aw_bits_size),
    .auto_axi4xbar_in_0_aw_bits_burst
      (_chi_llcBridge_opt_auto_axi4_out_aw_bits_burst),
    .auto_axi4xbar_in_0_aw_bits_qos
      (_chi_llcBridge_opt_auto_axi4_out_aw_bits_qos),
    .auto_axi4xbar_in_0_w_ready
      (_nocMisc_auto_axi4xbar_in_0_w_ready),
    .auto_axi4xbar_in_0_w_valid
      (_chi_llcBridge_opt_auto_axi4_out_w_valid),
    .auto_axi4xbar_in_0_w_bits_data
      (_chi_llcBridge_opt_auto_axi4_out_w_bits_data),
    .auto_axi4xbar_in_0_w_bits_strb
      (_chi_llcBridge_opt_auto_axi4_out_w_bits_strb),
    .auto_axi4xbar_in_0_w_bits_last
      (_chi_llcBridge_opt_auto_axi4_out_w_bits_last),
    .auto_axi4xbar_in_0_b_valid
      (_nocMisc_auto_axi4xbar_in_0_b_valid),
    .auto_axi4xbar_in_0_b_bits_id
      (_nocMisc_auto_axi4xbar_in_0_b_bits_id),
    .auto_axi4xbar_in_0_ar_ready
      (_nocMisc_auto_axi4xbar_in_0_ar_ready),
    .auto_axi4xbar_in_0_ar_valid
      (_chi_llcBridge_opt_auto_axi4_out_ar_valid),
    .auto_axi4xbar_in_0_ar_bits_id
      (_chi_llcBridge_opt_auto_axi4_out_ar_bits_id),
    .auto_axi4xbar_in_0_ar_bits_addr
      (_chi_llcBridge_opt_auto_axi4_out_ar_bits_addr),
    .auto_axi4xbar_in_0_ar_bits_len
      (_chi_llcBridge_opt_auto_axi4_out_ar_bits_len),
    .auto_axi4xbar_in_0_ar_bits_size
      (_chi_llcBridge_opt_auto_axi4_out_ar_bits_size),
    .auto_axi4xbar_in_0_ar_bits_burst
      (_chi_llcBridge_opt_auto_axi4_out_ar_bits_burst),
    .auto_axi4xbar_in_0_ar_bits_qos
      (_chi_llcBridge_opt_auto_axi4_out_ar_bits_qos),
    .auto_axi4xbar_in_0_r_valid
      (_nocMisc_auto_axi4xbar_in_0_r_valid),
    .auto_axi4xbar_in_0_r_bits_id
      (_nocMisc_auto_axi4xbar_in_0_r_bits_id),
    .auto_axi4xbar_in_0_r_bits_data
      (_nocMisc_auto_axi4xbar_in_0_r_bits_data),
    .auto_axi4xbar_in_0_r_bits_last
      (_nocMisc_auto_axi4xbar_in_0_r_bits_last),
    .memory_0_aw_ready                                  (memory_awready),
    .memory_0_aw_valid                                  (memory_awvalid),
    .memory_0_aw_bits_id                                (memory_awid),
    .memory_0_aw_bits_addr                              (memory_awaddr),
    .memory_0_aw_bits_len                               (memory_awlen),
    .memory_0_aw_bits_size                              (memory_awsize),
    .memory_0_aw_bits_burst                             (memory_awburst),
    .memory_0_aw_bits_lock                              (memory_awlock),
    .memory_0_aw_bits_cache                             (memory_awcache),
    .memory_0_aw_bits_prot                              (memory_awprot),
    .memory_0_aw_bits_qos                               (memory_awqos),
    .memory_0_w_ready                                   (memory_wready),
    .memory_0_w_valid                                   (memory_wvalid),
    .memory_0_w_bits_data                               (memory_wdata),
    .memory_0_w_bits_strb                               (memory_wstrb),
    .memory_0_w_bits_last                               (memory_wlast),
    .memory_0_b_ready                                   (memory_bready),
    .memory_0_b_valid                                   (memory_bvalid),
    .memory_0_b_bits_id                                 (memory_bid),
    .memory_0_b_bits_resp                               (memory_bresp),
    .memory_0_ar_ready                                  (memory_arready),
    .memory_0_ar_valid                                  (memory_arvalid),
    .memory_0_ar_bits_id                                (memory_arid),
    .memory_0_ar_bits_addr                              (memory_araddr),
    .memory_0_ar_bits_len                               (memory_arlen),
    .memory_0_ar_bits_size                              (memory_arsize),
    .memory_0_ar_bits_burst                             (memory_arburst),
    .memory_0_ar_bits_lock                              (memory_arlock),
    .memory_0_ar_bits_cache                             (memory_arcache),
    .memory_0_ar_bits_prot                              (memory_arprot),
    .memory_0_ar_bits_qos                               (memory_arqos),
    .memory_0_r_ready                                   (memory_rready),
    .memory_0_r_valid                                   (memory_rvalid),
    .memory_0_r_bits_id                                 (memory_rid),
    .memory_0_r_bits_data                               (memory_rdata),
    .memory_0_r_bits_resp                               (memory_rresp),
    .memory_0_r_bits_last                               (memory_rlast),
    .peripheral_0_aw_ready                              (peripheral_awready),
    .peripheral_0_aw_valid                              (peripheral_awvalid),
    .peripheral_0_aw_bits_id                            (peripheral_awid),
    .peripheral_0_aw_bits_addr                          (peripheral_awaddr),
    .peripheral_0_aw_bits_len                           (peripheral_awlen),
    .peripheral_0_aw_bits_size                          (peripheral_awsize),
    .peripheral_0_aw_bits_burst                         (peripheral_awburst),
    .peripheral_0_aw_bits_lock                          (peripheral_awlock),
    .peripheral_0_aw_bits_cache                         (peripheral_awcache),
    .peripheral_0_aw_bits_prot                          (peripheral_awprot),
    .peripheral_0_aw_bits_qos                           (peripheral_awqos),
    .peripheral_0_w_ready                               (peripheral_wready),
    .peripheral_0_w_valid                               (peripheral_wvalid),
    .peripheral_0_w_bits_data                           (peripheral_wdata),
    .peripheral_0_w_bits_strb                           (peripheral_wstrb),
    .peripheral_0_w_bits_last                           (peripheral_wlast),
    .peripheral_0_b_ready                               (peripheral_bready),
    .peripheral_0_b_valid                               (peripheral_bvalid),
    .peripheral_0_b_bits_id                             (peripheral_bid),
    .peripheral_0_b_bits_resp                           (peripheral_bresp),
    .peripheral_0_ar_ready                              (peripheral_arready),
    .peripheral_0_ar_valid                              (peripheral_arvalid),
    .peripheral_0_ar_bits_id                            (peripheral_arid),
    .peripheral_0_ar_bits_addr                          (peripheral_araddr),
    .peripheral_0_ar_bits_len                           (peripheral_arlen),
    .peripheral_0_ar_bits_size                          (peripheral_arsize),
    .peripheral_0_ar_bits_burst                         (peripheral_arburst),
    .peripheral_0_ar_bits_lock                          (peripheral_arlock),
    .peripheral_0_ar_bits_cache                         (peripheral_arcache),
    .peripheral_0_ar_bits_prot                          (peripheral_arprot),
    .peripheral_0_ar_bits_qos                           (peripheral_arqos),
    .peripheral_0_r_ready                               (peripheral_rready),
    .peripheral_0_r_valid                               (peripheral_rvalid),
    .peripheral_0_r_bits_id                             (peripheral_rid),
    .peripheral_0_r_bits_data                           (peripheral_rdata),
    .peripheral_0_r_bits_resp                           (peripheral_rresp),
    .peripheral_0_r_bits_last                           (peripheral_rlast),
    .debug_module_io_resetCtrl_hartResetReq_0
      (_nocMisc_debug_module_io_resetCtrl_hartResetReq_0),
    .debug_module_io_resetCtrl_hartIsInReset_0          (_core_with_l2_io_hartIsInReset),
    .debug_module_io_debugIO_clock                      (io_clock),
    .debug_module_io_debugIO_reset                      (_resetGen_o_reset),
    .debug_module_io_debugIO_systemjtag_jtag_TCK        (io_systemjtag_jtag_TCK),
    .debug_module_io_debugIO_systemjtag_jtag_TMS        (io_systemjtag_jtag_TMS),
    .debug_module_io_debugIO_systemjtag_jtag_TDI        (io_systemjtag_jtag_TDI),
    .debug_module_io_debugIO_systemjtag_jtag_TDO_data   (io_systemjtag_jtag_TDO_data),
    .debug_module_io_debugIO_systemjtag_jtag_TDO_driven (io_systemjtag_jtag_TDO_driven),
    .debug_module_io_debugIO_systemjtag_reset
      (_jtag_reset_sync_resetSync_o_reset),
    .debug_module_io_debugIO_systemjtag_mfr_id          (io_systemjtag_mfr_id),
    .debug_module_io_debugIO_systemjtag_part_number     (io_systemjtag_part_number),
    .debug_module_io_debugIO_systemjtag_version         (io_systemjtag_version),
    .debug_module_io_debugIO_ndreset                    (io_debug_reset),
    .debug_module_io_debugIO_dmactive
      (_nocMisc_debug_module_io_debugIO_dmactive),
    .debug_module_io_debugIO_dmactiveAck
      (_nocMisc_debug_module_io_debugIO_dmactive),
    .debug_module_io_clock                              (io_clock),
    .debug_module_io_reset                              (_reset_sync_resetSync_o_reset),
    .ext_intrs                                          (io_extIntrs),
    .rtc_clock                                          (io_rtc_clock),
    .rtc_reset
      (_ref_reset_sync_resetSync_o_reset),
    .bus_clock                                          (io_clock),
    .bus_reset                                          (io_reset),
    .pll0_lock                                          (io_pll0_lock),
    .pll0_ctrl_0                                        (io_pll0_ctrl_0),
    .pll0_ctrl_1                                        (io_pll0_ctrl_1),
    .pll0_ctrl_2                                        (io_pll0_ctrl_2),
    .pll0_ctrl_3                                        (io_pll0_ctrl_3),
    .pll0_ctrl_4                                        (io_pll0_ctrl_4),
    .pll0_ctrl_5                                        (io_pll0_ctrl_5),
    .cacheable_check_req_0_bits_addr
      (io_cacheable_check_req_0_bits_addr),
    .cacheable_check_req_1_bits_addr
      (io_cacheable_check_req_1_bits_addr),
    .cacheable_check_resp_0_ld                          (io_cacheable_check_resp_0_ld),
    .cacheable_check_resp_0_st                          (io_cacheable_check_resp_0_st),
    .cacheable_check_resp_0_instr                       (io_cacheable_check_resp_0_instr),
    .cacheable_check_resp_0_mmio                        (io_cacheable_check_resp_0_mmio),
    .cacheable_check_resp_0_atomic
      (io_cacheable_check_resp_0_atomic),
    .cacheable_check_resp_1_ld                          (io_cacheable_check_resp_1_ld),
    .cacheable_check_resp_1_st                          (io_cacheable_check_resp_1_st),
    .cacheable_check_resp_1_instr                       (io_cacheable_check_resp_1_instr),
    .cacheable_check_resp_1_mmio                        (io_cacheable_check_resp_1_mmio),
    .cacheable_check_resp_1_atomic
      (io_cacheable_check_resp_1_atomic),
    .clintTime_valid                                    (_nocMisc_clintTime_valid),
    .clintTime_bits                                     (_nocMisc_clintTime_bits)
  );
  XSTile core_with_l2 (
    .clock                                                   (io_clock),
    .reset                                                   (_resetGen_1_o_reset),
    .auto_l2top_inner_beu_int_out_0
      (_core_with_l2_auto_l2top_inner_beu_int_out_0),
    .auto_l2top_inner_nmi_int_in_0                           (nmi_0_0),
    .auto_l2top_inner_nmi_int_in_1                           (nmi_0_1),
    .auto_l2top_inner_plic_int_in_1_0
      (_nocMisc_auto_plic_int_out_1_0),
    .auto_l2top_inner_plic_int_in_0_0
      (_nocMisc_auto_plic_int_out_0_0),
    .auto_l2top_inner_debug_int_in_0
      (_nocMisc_auto_debugModule_debug_dmOuter_dmOuter_int_out_0),
    .auto_l2top_inner_clint_int_in_0
      (_nocMisc_auto_timer_int_out_0),
    .auto_l2top_inner_clint_int_in_1
      (_nocMisc_auto_timer_int_out_1),
    .io_hartId                                               (6'h0),
    .io_msiInfo_valid                                        (1'h0),
    .io_msiInfo_bits                                         (13'h0),
    .io_reset_vector                                         (io_riscv_rst_vec_0),
    .io_cpu_wfi                                              (io_riscv_wfi_0),
    .io_cpu_crtical_error                                    (io_riscv_critical_error_0),
    .io_hartIsInReset
      (_core_with_l2_io_hartIsInReset),
    .io_traceCoreInterface_fromEncoder_enable
      (io_traceCoreInterface_0_fromEncoder_enable),
    .io_traceCoreInterface_fromEncoder_stall
      (io_traceCoreInterface_0_fromEncoder_stall),
    .io_traceCoreInterface_toEncoder_priv
      (io_traceCoreInterface_0_toEncoder_priv),
    .io_traceCoreInterface_toEncoder_mstatus
      (io_traceCoreInterface_0_toEncoder_mstatus),
    .io_traceCoreInterface_toEncoder_trap_cause
      (io_traceCoreInterface_0_toEncoder_cause),
    .io_traceCoreInterface_toEncoder_trap_tval
      (io_traceCoreInterface_0_toEncoder_tval),
    .io_traceCoreInterface_toEncoder_groups_0_valid
      (_core_with_l2_io_traceCoreInterface_toEncoder_groups_0_valid),
    .io_traceCoreInterface_toEncoder_groups_0_bits_iaddr
      (_core_with_l2_io_traceCoreInterface_toEncoder_groups_0_bits_iaddr),
    .io_traceCoreInterface_toEncoder_groups_0_bits_itype
      (_core_with_l2_io_traceCoreInterface_toEncoder_groups_0_bits_itype),
    .io_traceCoreInterface_toEncoder_groups_0_bits_iretire
      (_core_with_l2_io_traceCoreInterface_toEncoder_groups_0_bits_iretire),
    .io_traceCoreInterface_toEncoder_groups_0_bits_ilastsize
      (_core_with_l2_io_traceCoreInterface_toEncoder_groups_0_bits_ilastsize),
    .io_traceCoreInterface_toEncoder_groups_1_valid
      (_core_with_l2_io_traceCoreInterface_toEncoder_groups_1_valid),
    .io_traceCoreInterface_toEncoder_groups_1_bits_iaddr
      (_core_with_l2_io_traceCoreInterface_toEncoder_groups_1_bits_iaddr),
    .io_traceCoreInterface_toEncoder_groups_1_bits_itype
      (_core_with_l2_io_traceCoreInterface_toEncoder_groups_1_bits_itype),
    .io_traceCoreInterface_toEncoder_groups_1_bits_iretire
      (_core_with_l2_io_traceCoreInterface_toEncoder_groups_1_bits_iretire),
    .io_traceCoreInterface_toEncoder_groups_1_bits_ilastsize
      (_core_with_l2_io_traceCoreInterface_toEncoder_groups_1_bits_ilastsize),
    .io_traceCoreInterface_toEncoder_groups_2_valid
      (_core_with_l2_io_traceCoreInterface_toEncoder_groups_2_valid),
    .io_traceCoreInterface_toEncoder_groups_2_bits_iaddr
      (_core_with_l2_io_traceCoreInterface_toEncoder_groups_2_bits_iaddr),
    .io_traceCoreInterface_toEncoder_groups_2_bits_itype
      (_core_with_l2_io_traceCoreInterface_toEncoder_groups_2_bits_itype),
    .io_traceCoreInterface_toEncoder_groups_2_bits_iretire
      (_core_with_l2_io_traceCoreInterface_toEncoder_groups_2_bits_iretire),
    .io_traceCoreInterface_toEncoder_groups_2_bits_ilastsize
      (_core_with_l2_io_traceCoreInterface_toEncoder_groups_2_bits_ilastsize),
    .io_l3Miss                                               (_chi_openllc_opt_io_l3Miss),
    .io_chi_txsactive
      (_core_with_l2_io_chi_txsactive),
    .io_chi_rxsactive
      (_linkMonitor_io_in_rxsactive),
    .io_chi_syscoreq
      (_core_with_l2_io_chi_syscoreq),
    .io_chi_syscoack
      (_linkMonitor_io_in_syscoack),
    .io_chi_tx_linkactivereq
      (_core_with_l2_io_chi_tx_linkactivereq),
    .io_chi_tx_linkactiveack
      (_linkMonitor_io_in_tx_linkactiveack),
    .io_chi_tx_req_flitpend
      (_core_with_l2_io_chi_tx_req_flitpend),
    .io_chi_tx_req_flitv
      (_core_with_l2_io_chi_tx_req_flitv),
    .io_chi_tx_req_flit
      (_core_with_l2_io_chi_tx_req_flit),
    .io_chi_tx_req_lcrdv
      (_linkMonitor_io_in_tx_req_lcrdv),
    .io_chi_tx_rsp_flitpend
      (_core_with_l2_io_chi_tx_rsp_flitpend),
    .io_chi_tx_rsp_flitv
      (_core_with_l2_io_chi_tx_rsp_flitv),
    .io_chi_tx_rsp_flit
      (_core_with_l2_io_chi_tx_rsp_flit),
    .io_chi_tx_rsp_lcrdv
      (_linkMonitor_io_in_tx_rsp_lcrdv),
    .io_chi_tx_dat_flitpend
      (_core_with_l2_io_chi_tx_dat_flitpend),
    .io_chi_tx_dat_flitv
      (_core_with_l2_io_chi_tx_dat_flitv),
    .io_chi_tx_dat_flit
      (_core_with_l2_io_chi_tx_dat_flit),
    .io_chi_tx_dat_lcrdv
      (_linkMonitor_io_in_tx_dat_lcrdv),
    .io_chi_rx_linkactivereq
      (_linkMonitor_io_in_rx_linkactivereq),
    .io_chi_rx_linkactiveack
      (_core_with_l2_io_chi_rx_linkactiveack),
    .io_chi_rx_rsp_flitpend
      (_linkMonitor_io_in_rx_rsp_flitpend),
    .io_chi_rx_rsp_flitv
      (_linkMonitor_io_in_rx_rsp_flitv),
    .io_chi_rx_rsp_flit
      (_linkMonitor_io_in_rx_rsp_flit),
    .io_chi_rx_rsp_lcrdv
      (_core_with_l2_io_chi_rx_rsp_lcrdv),
    .io_chi_rx_dat_flitpend
      (_linkMonitor_io_in_rx_dat_flitpend),
    .io_chi_rx_dat_flitv
      (_linkMonitor_io_in_rx_dat_flitv),
    .io_chi_rx_dat_flit
      (_linkMonitor_io_in_rx_dat_flit),
    .io_chi_rx_dat_lcrdv
      (_core_with_l2_io_chi_rx_dat_lcrdv),
    .io_chi_rx_snp_flitpend
      (_linkMonitor_io_in_rx_snp_flitpend),
    .io_chi_rx_snp_flitv
      (_linkMonitor_io_in_rx_snp_flitv),
    .io_chi_rx_snp_flit
      (_linkMonitor_io_in_rx_snp_flit),
    .io_chi_rx_snp_lcrdv
      (_core_with_l2_io_chi_rx_snp_lcrdv),
    .io_nodeID                                               (11'h0),
    .io_clintTime_valid                                      (_nocMisc_clintTime_valid),
    .io_clintTime_bits                                       (_nocMisc_clintTime_bits),
    .io_dft_ram_hold                                         (1'h0),
    .io_dft_ram_bypass                                       (1'h0),
    .io_dft_ram_bp_clken                                     (1'h0),
    .io_dft_ram_aux_clk                                      (1'h0),
    .io_dft_ram_aux_ckbp                                     (1'h0),
    .io_dft_ram_mcp_hold                                     (1'h0),
    .io_dft_ram_ctl                                          (64'h0),
    .io_dft_cgen                                             (1'h0),
    .io_dft_reset_lgc_rst_n                                  (1'h0),
    .io_dft_reset_mode                                       (1'h0),
    .io_dft_reset_scan_mode                                  (1'h0)
  );
  OpenNCB chi_llcBridge_opt (
    .clock                       (io_clock),
    .reset                       (_reset_sync_resetSync_o_reset),
    .auto_axi4_out_aw_ready      (_nocMisc_auto_axi4xbar_in_0_aw_ready),
    .auto_axi4_out_aw_valid      (_chi_llcBridge_opt_auto_axi4_out_aw_valid),
    .auto_axi4_out_aw_bits_id    (_chi_llcBridge_opt_auto_axi4_out_aw_bits_id),
    .auto_axi4_out_aw_bits_addr  (_chi_llcBridge_opt_auto_axi4_out_aw_bits_addr),
    .auto_axi4_out_aw_bits_len   (_chi_llcBridge_opt_auto_axi4_out_aw_bits_len),
    .auto_axi4_out_aw_bits_size  (_chi_llcBridge_opt_auto_axi4_out_aw_bits_size),
    .auto_axi4_out_aw_bits_burst (_chi_llcBridge_opt_auto_axi4_out_aw_bits_burst),
    .auto_axi4_out_aw_bits_qos   (_chi_llcBridge_opt_auto_axi4_out_aw_bits_qos),
    .auto_axi4_out_w_ready       (_nocMisc_auto_axi4xbar_in_0_w_ready),
    .auto_axi4_out_w_valid       (_chi_llcBridge_opt_auto_axi4_out_w_valid),
    .auto_axi4_out_w_bits_data   (_chi_llcBridge_opt_auto_axi4_out_w_bits_data),
    .auto_axi4_out_w_bits_strb   (_chi_llcBridge_opt_auto_axi4_out_w_bits_strb),
    .auto_axi4_out_w_bits_last   (_chi_llcBridge_opt_auto_axi4_out_w_bits_last),
    .auto_axi4_out_b_valid       (_nocMisc_auto_axi4xbar_in_0_b_valid),
    .auto_axi4_out_b_bits_id     (_nocMisc_auto_axi4xbar_in_0_b_bits_id),
    .auto_axi4_out_ar_ready      (_nocMisc_auto_axi4xbar_in_0_ar_ready),
    .auto_axi4_out_ar_valid      (_chi_llcBridge_opt_auto_axi4_out_ar_valid),
    .auto_axi4_out_ar_bits_id    (_chi_llcBridge_opt_auto_axi4_out_ar_bits_id),
    .auto_axi4_out_ar_bits_addr  (_chi_llcBridge_opt_auto_axi4_out_ar_bits_addr),
    .auto_axi4_out_ar_bits_len   (_chi_llcBridge_opt_auto_axi4_out_ar_bits_len),
    .auto_axi4_out_ar_bits_size  (_chi_llcBridge_opt_auto_axi4_out_ar_bits_size),
    .auto_axi4_out_ar_bits_burst (_chi_llcBridge_opt_auto_axi4_out_ar_bits_burst),
    .auto_axi4_out_ar_bits_qos   (_chi_llcBridge_opt_auto_axi4_out_ar_bits_qos),
    .auto_axi4_out_r_valid       (_nocMisc_auto_axi4xbar_in_0_r_valid),
    .auto_axi4_out_r_bits_id     (_nocMisc_auto_axi4xbar_in_0_r_bits_id),
    .auto_axi4_out_r_bits_data   (_nocMisc_auto_axi4xbar_in_0_r_bits_data),
    .auto_axi4_out_r_bits_last   (_nocMisc_auto_axi4xbar_in_0_r_bits_last),
    .io_chi_txsactive            (_memLogger_io_down_txsactive),
    .io_chi_rxsactive            (_chi_llcBridge_opt_io_chi_rxsactive),
    .io_chi_tx_linkactivereq     (_memLogger_io_down_tx_linkactivereq),
    .io_chi_tx_linkactiveack     (_chi_llcBridge_opt_io_chi_tx_linkactiveack),
    .io_chi_tx_req_flitpend      (_memLogger_io_down_tx_req_flitpend),
    .io_chi_tx_req_flitv         (_memLogger_io_down_tx_req_flitv),
    .io_chi_tx_req_flit          (_memLogger_io_down_tx_req_flit),
    .io_chi_tx_req_lcrdv         (_chi_llcBridge_opt_io_chi_tx_req_lcrdv),
    .io_chi_tx_dat_flitpend      (_memLogger_io_down_tx_dat_flitpend),
    .io_chi_tx_dat_flitv         (_memLogger_io_down_tx_dat_flitv),
    .io_chi_tx_dat_flit          (_memLogger_io_down_tx_dat_flit),
    .io_chi_tx_dat_lcrdv         (_chi_llcBridge_opt_io_chi_tx_dat_lcrdv),
    .io_chi_rx_linkactivereq     (_chi_llcBridge_opt_io_chi_rx_linkactivereq),
    .io_chi_rx_linkactiveack     (_memLogger_io_down_rx_linkactiveack),
    .io_chi_rx_rsp_flitpend      (_chi_llcBridge_opt_io_chi_rx_rsp_flitpend),
    .io_chi_rx_rsp_flitv         (_chi_llcBridge_opt_io_chi_rx_rsp_flitv),
    .io_chi_rx_rsp_flit          (_chi_llcBridge_opt_io_chi_rx_rsp_flit),
    .io_chi_rx_rsp_lcrdv         (_memLogger_io_down_rx_rsp_lcrdv),
    .io_chi_rx_dat_flitpend      (_chi_llcBridge_opt_io_chi_rx_dat_flitpend),
    .io_chi_rx_dat_flitv         (_chi_llcBridge_opt_io_chi_rx_dat_flitv),
    .io_chi_rx_dat_flit          (_chi_llcBridge_opt_io_chi_rx_dat_flit),
    .io_chi_rx_dat_lcrdv         (_memLogger_io_down_rx_dat_lcrdv)
  );
  OpenNCB_1 chi_mmioBridge_opt (
    .clock                       (io_clock),
    .reset                       (_reset_sync_resetSync_o_reset),
    .auto_axi4_out_aw_ready      (_nocMisc_auto_axi4xbar_in_1_aw_ready),
    .auto_axi4_out_aw_valid      (_chi_mmioBridge_opt_auto_axi4_out_aw_valid),
    .auto_axi4_out_aw_bits_id    (_chi_mmioBridge_opt_auto_axi4_out_aw_bits_id),
    .auto_axi4_out_aw_bits_addr  (_chi_mmioBridge_opt_auto_axi4_out_aw_bits_addr),
    .auto_axi4_out_aw_bits_len   (_chi_mmioBridge_opt_auto_axi4_out_aw_bits_len),
    .auto_axi4_out_aw_bits_size  (_chi_mmioBridge_opt_auto_axi4_out_aw_bits_size),
    .auto_axi4_out_aw_bits_burst (_chi_mmioBridge_opt_auto_axi4_out_aw_bits_burst),
    .auto_axi4_out_aw_bits_cache (_chi_mmioBridge_opt_auto_axi4_out_aw_bits_cache),
    .auto_axi4_out_aw_bits_qos   (_chi_mmioBridge_opt_auto_axi4_out_aw_bits_qos),
    .auto_axi4_out_w_ready       (_nocMisc_auto_axi4xbar_in_1_w_ready),
    .auto_axi4_out_w_valid       (_chi_mmioBridge_opt_auto_axi4_out_w_valid),
    .auto_axi4_out_w_bits_data   (_chi_mmioBridge_opt_auto_axi4_out_w_bits_data),
    .auto_axi4_out_w_bits_strb   (_chi_mmioBridge_opt_auto_axi4_out_w_bits_strb),
    .auto_axi4_out_w_bits_last   (_chi_mmioBridge_opt_auto_axi4_out_w_bits_last),
    .auto_axi4_out_b_valid       (_nocMisc_auto_axi4xbar_in_1_b_valid),
    .auto_axi4_out_b_bits_id     (_nocMisc_auto_axi4xbar_in_1_b_bits_id),
    .auto_axi4_out_ar_ready      (_nocMisc_auto_axi4xbar_in_1_ar_ready),
    .auto_axi4_out_ar_valid      (_chi_mmioBridge_opt_auto_axi4_out_ar_valid),
    .auto_axi4_out_ar_bits_id    (_chi_mmioBridge_opt_auto_axi4_out_ar_bits_id),
    .auto_axi4_out_ar_bits_addr  (_chi_mmioBridge_opt_auto_axi4_out_ar_bits_addr),
    .auto_axi4_out_ar_bits_len   (_chi_mmioBridge_opt_auto_axi4_out_ar_bits_len),
    .auto_axi4_out_ar_bits_size  (_chi_mmioBridge_opt_auto_axi4_out_ar_bits_size),
    .auto_axi4_out_ar_bits_burst (_chi_mmioBridge_opt_auto_axi4_out_ar_bits_burst),
    .auto_axi4_out_ar_bits_cache (_chi_mmioBridge_opt_auto_axi4_out_ar_bits_cache),
    .auto_axi4_out_ar_bits_qos   (_chi_mmioBridge_opt_auto_axi4_out_ar_bits_qos),
    .auto_axi4_out_r_valid       (_nocMisc_auto_axi4xbar_in_1_r_valid),
    .auto_axi4_out_r_bits_id     (_nocMisc_auto_axi4xbar_in_1_r_bits_id),
    .auto_axi4_out_r_bits_data   (_nocMisc_auto_axi4xbar_in_1_r_bits_data),
    .auto_axi4_out_r_bits_last   (_nocMisc_auto_axi4xbar_in_1_r_bits_last),
    .io_chi_txsactive            (_mmioLogger_io_down_txsactive),
    .io_chi_rxsactive            (_chi_mmioBridge_opt_io_chi_rxsactive),
    .io_chi_tx_linkactivereq     (_mmioLogger_io_down_tx_linkactivereq),
    .io_chi_tx_linkactiveack     (_chi_mmioBridge_opt_io_chi_tx_linkactiveack),
    .io_chi_tx_req_flitpend      (_mmioLogger_io_down_tx_req_flitpend),
    .io_chi_tx_req_flitv         (_mmioLogger_io_down_tx_req_flitv),
    .io_chi_tx_req_flit          (_mmioLogger_io_down_tx_req_flit),
    .io_chi_tx_req_lcrdv         (_chi_mmioBridge_opt_io_chi_tx_req_lcrdv),
    .io_chi_tx_dat_flitpend      (_mmioLogger_io_down_tx_dat_flitpend),
    .io_chi_tx_dat_flitv         (_mmioLogger_io_down_tx_dat_flitv),
    .io_chi_tx_dat_flit          (_mmioLogger_io_down_tx_dat_flit),
    .io_chi_tx_dat_lcrdv         (_chi_mmioBridge_opt_io_chi_tx_dat_lcrdv),
    .io_chi_rx_linkactivereq     (_chi_mmioBridge_opt_io_chi_rx_linkactivereq),
    .io_chi_rx_linkactiveack     (_mmioLogger_io_down_rx_linkactiveack),
    .io_chi_rx_rsp_flitpend      (_chi_mmioBridge_opt_io_chi_rx_rsp_flitpend),
    .io_chi_rx_rsp_flitv         (_chi_mmioBridge_opt_io_chi_rx_rsp_flitv),
    .io_chi_rx_rsp_flit          (_chi_mmioBridge_opt_io_chi_rx_rsp_flit),
    .io_chi_rx_rsp_lcrdv         (_mmioLogger_io_down_rx_rsp_lcrdv),
    .io_chi_rx_dat_flitpend      (_chi_mmioBridge_opt_io_chi_rx_dat_flitpend),
    .io_chi_rx_dat_flitv         (_chi_mmioBridge_opt_io_chi_rx_dat_flitv),
    .io_chi_rx_dat_flit          (_chi_mmioBridge_opt_io_chi_rx_dat_flit),
    .io_chi_rx_dat_lcrdv         (_mmioLogger_io_down_rx_dat_lcrdv)
  );
  IntBuffer intBuffer (
    .clock      (io_clock),
    .reset      (_reset_sync_resetSync_o_reset),
    .auto_in_0  (_core_with_l2_auto_l2top_inner_beu_int_out_0),
    .auto_out_0 (_intBuffer_auto_out_0)
  );
  ResetGen reset_sync_resetSync (
    .clock         (io_clock),
    .reset         (io_reset),
    .o_reset       (_reset_sync_resetSync_o_reset),
    .dft_lgc_rst_n (1'h0),
    .dft_mode      (1'h0),
    .dft_scan_mode (1'h0)
  );
  ResetGen jtag_reset_sync_resetSync (
    .clock         (io_systemjtag_jtag_TCK),
    .reset         (io_systemjtag_reset),
    .o_reset       (_jtag_reset_sync_resetSync_o_reset),
    .dft_lgc_rst_n (1'h0),
    .dft_mode      (1'h0),
    .dft_scan_mode (1'h0)
  );
  OpenLLC chi_openllc_opt (
    .clock                    (io_clock),
    .reset                    (io_reset),
    .io_rn_0_txsactive        (_llcLogger_io_down_txsactive),
    .io_rn_0_rxsactive        (_chi_openllc_opt_io_rn_0_rxsactive),
    .io_rn_0_syscoreq         (_llcLogger_io_down_syscoreq),
    .io_rn_0_syscoack         (_chi_openllc_opt_io_rn_0_syscoack),
    .io_rn_0_tx_linkactivereq (_llcLogger_io_down_tx_linkactivereq),
    .io_rn_0_tx_linkactiveack (_chi_openllc_opt_io_rn_0_tx_linkactiveack),
    .io_rn_0_tx_req_flitpend  (_llcLogger_io_down_tx_req_flitpend),
    .io_rn_0_tx_req_flitv     (_llcLogger_io_down_tx_req_flitv),
    .io_rn_0_tx_req_flit      (_llcLogger_io_down_tx_req_flit),
    .io_rn_0_tx_req_lcrdv     (_chi_openllc_opt_io_rn_0_tx_req_lcrdv),
    .io_rn_0_tx_rsp_flitpend  (_llcLogger_io_down_tx_rsp_flitpend),
    .io_rn_0_tx_rsp_flitv     (_llcLogger_io_down_tx_rsp_flitv),
    .io_rn_0_tx_rsp_flit      (_llcLogger_io_down_tx_rsp_flit),
    .io_rn_0_tx_rsp_lcrdv     (_chi_openllc_opt_io_rn_0_tx_rsp_lcrdv),
    .io_rn_0_tx_dat_flitpend  (_llcLogger_io_down_tx_dat_flitpend),
    .io_rn_0_tx_dat_flitv     (_llcLogger_io_down_tx_dat_flitv),
    .io_rn_0_tx_dat_flit      (_llcLogger_io_down_tx_dat_flit),
    .io_rn_0_tx_dat_lcrdv     (_chi_openllc_opt_io_rn_0_tx_dat_lcrdv),
    .io_rn_0_rx_linkactivereq (_chi_openllc_opt_io_rn_0_rx_linkactivereq),
    .io_rn_0_rx_linkactiveack (_llcLogger_io_down_rx_linkactiveack),
    .io_rn_0_rx_rsp_flitpend  (_chi_openllc_opt_io_rn_0_rx_rsp_flitpend),
    .io_rn_0_rx_rsp_flitv     (_chi_openllc_opt_io_rn_0_rx_rsp_flitv),
    .io_rn_0_rx_rsp_flit      (_chi_openllc_opt_io_rn_0_rx_rsp_flit),
    .io_rn_0_rx_rsp_lcrdv     (_llcLogger_io_down_rx_rsp_lcrdv),
    .io_rn_0_rx_dat_flitpend  (_chi_openllc_opt_io_rn_0_rx_dat_flitpend),
    .io_rn_0_rx_dat_flitv     (_chi_openllc_opt_io_rn_0_rx_dat_flitv),
    .io_rn_0_rx_dat_flit      (_chi_openllc_opt_io_rn_0_rx_dat_flit),
    .io_rn_0_rx_dat_lcrdv     (_llcLogger_io_down_rx_dat_lcrdv),
    .io_rn_0_rx_snp_flitpend  (_chi_openllc_opt_io_rn_0_rx_snp_flitpend),
    .io_rn_0_rx_snp_flitv     (_chi_openllc_opt_io_rn_0_rx_snp_flitv),
    .io_rn_0_rx_snp_flit      (_chi_openllc_opt_io_rn_0_rx_snp_flit),
    .io_rn_0_rx_snp_lcrdv     (_llcLogger_io_down_rx_snp_lcrdv),
    .io_sn_txsactive          (_chi_openllc_opt_io_sn_txsactive),
    .io_sn_rxsactive          (_memLogger_io_up_rxsactive),
    .io_sn_tx_linkactivereq   (_chi_openllc_opt_io_sn_tx_linkactivereq),
    .io_sn_tx_linkactiveack   (_memLogger_io_up_tx_linkactiveack),
    .io_sn_tx_req_flitpend    (_chi_openllc_opt_io_sn_tx_req_flitpend),
    .io_sn_tx_req_flitv       (_chi_openllc_opt_io_sn_tx_req_flitv),
    .io_sn_tx_req_flit        (_chi_openllc_opt_io_sn_tx_req_flit),
    .io_sn_tx_req_lcrdv       (_memLogger_io_up_tx_req_lcrdv),
    .io_sn_tx_dat_flitpend    (_chi_openllc_opt_io_sn_tx_dat_flitpend),
    .io_sn_tx_dat_flitv       (_chi_openllc_opt_io_sn_tx_dat_flitv),
    .io_sn_tx_dat_flit        (_chi_openllc_opt_io_sn_tx_dat_flit),
    .io_sn_tx_dat_lcrdv       (_memLogger_io_up_tx_dat_lcrdv),
    .io_sn_rx_linkactivereq   (_memLogger_io_up_rx_linkactivereq),
    .io_sn_rx_linkactiveack   (_chi_openllc_opt_io_sn_rx_linkactiveack),
    .io_sn_rx_rsp_flitpend    (_memLogger_io_up_rx_rsp_flitpend),
    .io_sn_rx_rsp_flitv       (_memLogger_io_up_rx_rsp_flitv),
    .io_sn_rx_rsp_flit        (_memLogger_io_up_rx_rsp_flit),
    .io_sn_rx_rsp_lcrdv       (_chi_openllc_opt_io_sn_rx_rsp_lcrdv),
    .io_sn_rx_dat_flitpend    (_memLogger_io_up_rx_dat_flitpend),
    .io_sn_rx_dat_flitv       (_memLogger_io_up_rx_dat_flitv),
    .io_sn_rx_dat_flit        (_memLogger_io_up_rx_dat_flit),
    .io_sn_rx_dat_lcrdv       (_chi_openllc_opt_io_sn_rx_dat_lcrdv),
    .io_l3Miss                (_chi_openllc_opt_io_l3Miss)
  );
  ResetGen ref_reset_sync_resetSync (
    .clock         (io_rtc_clock),
    .reset         (io_reset),
    .o_reset       (_ref_reset_sync_resetSync_o_reset),
    .dft_lgc_rst_n (1'h0),
    .dft_mode      (1'h0),
    .dft_scan_mode (1'h0)
  );
  CHILogger mmioLogger (
    .io_up_txsactive          (_linkMonitor_2_io_out_txsactive),
    .io_up_rxsactive          (_mmioLogger_io_up_rxsactive),
    .io_up_syscoreq           (_linkMonitor_2_io_out_syscoreq),
    .io_up_syscoack           (_mmioLogger_io_up_syscoack),
    .io_up_tx_linkactivereq   (_linkMonitor_2_io_out_tx_linkactivereq),
    .io_up_tx_linkactiveack   (_mmioLogger_io_up_tx_linkactiveack),
    .io_up_tx_req_flitpend    (_linkMonitor_2_io_out_tx_req_flitpend),
    .io_up_tx_req_flitv       (_linkMonitor_2_io_out_tx_req_flitv),
    .io_up_tx_req_flit        (_linkMonitor_2_io_out_tx_req_flit),
    .io_up_tx_req_lcrdv       (_mmioLogger_io_up_tx_req_lcrdv),
    .io_up_tx_rsp_flitpend    (_linkMonitor_2_io_out_tx_rsp_flitpend),
    .io_up_tx_rsp_flitv       (_linkMonitor_2_io_out_tx_rsp_flitv),
    .io_up_tx_rsp_flit        (_linkMonitor_2_io_out_tx_rsp_flit),
    .io_up_tx_rsp_lcrdv       (_mmioLogger_io_up_tx_rsp_lcrdv),
    .io_up_tx_dat_flitpend    (_linkMonitor_2_io_out_tx_dat_flitpend),
    .io_up_tx_dat_flitv       (_linkMonitor_2_io_out_tx_dat_flitv),
    .io_up_tx_dat_flit        (_linkMonitor_2_io_out_tx_dat_flit),
    .io_up_tx_dat_lcrdv       (_mmioLogger_io_up_tx_dat_lcrdv),
    .io_up_rx_linkactivereq   (_mmioLogger_io_up_rx_linkactivereq),
    .io_up_rx_linkactiveack   (_linkMonitor_2_io_out_rx_linkactiveack),
    .io_up_rx_rsp_flitpend    (_mmioLogger_io_up_rx_rsp_flitpend),
    .io_up_rx_rsp_flitv       (_mmioLogger_io_up_rx_rsp_flitv),
    .io_up_rx_rsp_flit        (_mmioLogger_io_up_rx_rsp_flit),
    .io_up_rx_rsp_lcrdv       (_linkMonitor_2_io_out_rx_rsp_lcrdv),
    .io_up_rx_dat_flitpend    (_mmioLogger_io_up_rx_dat_flitpend),
    .io_up_rx_dat_flitv       (_mmioLogger_io_up_rx_dat_flitv),
    .io_up_rx_dat_flit        (_mmioLogger_io_up_rx_dat_flit),
    .io_up_rx_dat_lcrdv       (_linkMonitor_2_io_out_rx_dat_lcrdv),
    .io_up_rx_snp_flitpend    (_mmioLogger_io_up_rx_snp_flitpend),
    .io_up_rx_snp_flitv       (_mmioLogger_io_up_rx_snp_flitv),
    .io_up_rx_snp_flit        (_mmioLogger_io_up_rx_snp_flit),
    .io_up_rx_snp_lcrdv       (_linkMonitor_2_io_out_rx_snp_lcrdv),
    .io_down_txsactive        (_mmioLogger_io_down_txsactive),
    .io_down_rxsactive        (_chi_mmioBridge_opt_io_chi_rxsactive),
    .io_down_syscoreq         (/* unused */),
    .io_down_syscoack         (1'h0),
    .io_down_tx_linkactivereq (_mmioLogger_io_down_tx_linkactivereq),
    .io_down_tx_linkactiveack (_chi_mmioBridge_opt_io_chi_tx_linkactiveack),
    .io_down_tx_req_flitpend  (_mmioLogger_io_down_tx_req_flitpend),
    .io_down_tx_req_flitv     (_mmioLogger_io_down_tx_req_flitv),
    .io_down_tx_req_flit      (_mmioLogger_io_down_tx_req_flit),
    .io_down_tx_req_lcrdv     (_chi_mmioBridge_opt_io_chi_tx_req_lcrdv),
    .io_down_tx_rsp_flitpend  (/* unused */),
    .io_down_tx_rsp_flitv     (/* unused */),
    .io_down_tx_rsp_flit      (/* unused */),
    .io_down_tx_rsp_lcrdv     (1'h0),
    .io_down_tx_dat_flitpend  (_mmioLogger_io_down_tx_dat_flitpend),
    .io_down_tx_dat_flitv     (_mmioLogger_io_down_tx_dat_flitv),
    .io_down_tx_dat_flit      (_mmioLogger_io_down_tx_dat_flit),
    .io_down_tx_dat_lcrdv     (_chi_mmioBridge_opt_io_chi_tx_dat_lcrdv),
    .io_down_rx_linkactivereq (_chi_mmioBridge_opt_io_chi_rx_linkactivereq),
    .io_down_rx_linkactiveack (_mmioLogger_io_down_rx_linkactiveack),
    .io_down_rx_rsp_flitpend  (_chi_mmioBridge_opt_io_chi_rx_rsp_flitpend),
    .io_down_rx_rsp_flitv     (_chi_mmioBridge_opt_io_chi_rx_rsp_flitv),
    .io_down_rx_rsp_flit      (_chi_mmioBridge_opt_io_chi_rx_rsp_flit),
    .io_down_rx_rsp_lcrdv     (_mmioLogger_io_down_rx_rsp_lcrdv),
    .io_down_rx_dat_flitpend  (_chi_mmioBridge_opt_io_chi_rx_dat_flitpend),
    .io_down_rx_dat_flitv     (_chi_mmioBridge_opt_io_chi_rx_dat_flitv),
    .io_down_rx_dat_flit      (_chi_mmioBridge_opt_io_chi_rx_dat_flit),
    .io_down_rx_dat_lcrdv     (_mmioLogger_io_down_rx_dat_lcrdv),
    .io_down_rx_snp_flitpend  (1'h0),
    .io_down_rx_snp_flitv     (1'h0),
    .io_down_rx_snp_flit      (115'h0),
    .io_down_rx_snp_lcrdv     (/* unused */)
  );
  CHILogger llcLogger (
    .io_up_txsactive          (_linkMonitor_1_io_out_txsactive),
    .io_up_rxsactive          (_llcLogger_io_up_rxsactive),
    .io_up_syscoreq           (_linkMonitor_1_io_out_syscoreq),
    .io_up_syscoack           (_llcLogger_io_up_syscoack),
    .io_up_tx_linkactivereq   (_linkMonitor_1_io_out_tx_linkactivereq),
    .io_up_tx_linkactiveack   (_llcLogger_io_up_tx_linkactiveack),
    .io_up_tx_req_flitpend    (_linkMonitor_1_io_out_tx_req_flitpend),
    .io_up_tx_req_flitv       (_linkMonitor_1_io_out_tx_req_flitv),
    .io_up_tx_req_flit        (_linkMonitor_1_io_out_tx_req_flit),
    .io_up_tx_req_lcrdv       (_llcLogger_io_up_tx_req_lcrdv),
    .io_up_tx_rsp_flitpend    (_linkMonitor_1_io_out_tx_rsp_flitpend),
    .io_up_tx_rsp_flitv       (_linkMonitor_1_io_out_tx_rsp_flitv),
    .io_up_tx_rsp_flit        (_linkMonitor_1_io_out_tx_rsp_flit),
    .io_up_tx_rsp_lcrdv       (_llcLogger_io_up_tx_rsp_lcrdv),
    .io_up_tx_dat_flitpend    (_linkMonitor_1_io_out_tx_dat_flitpend),
    .io_up_tx_dat_flitv       (_linkMonitor_1_io_out_tx_dat_flitv),
    .io_up_tx_dat_flit        (_linkMonitor_1_io_out_tx_dat_flit),
    .io_up_tx_dat_lcrdv       (_llcLogger_io_up_tx_dat_lcrdv),
    .io_up_rx_linkactivereq   (_llcLogger_io_up_rx_linkactivereq),
    .io_up_rx_linkactiveack   (_linkMonitor_1_io_out_rx_linkactiveack),
    .io_up_rx_rsp_flitpend    (_llcLogger_io_up_rx_rsp_flitpend),
    .io_up_rx_rsp_flitv       (_llcLogger_io_up_rx_rsp_flitv),
    .io_up_rx_rsp_flit        (_llcLogger_io_up_rx_rsp_flit),
    .io_up_rx_rsp_lcrdv       (_linkMonitor_1_io_out_rx_rsp_lcrdv),
    .io_up_rx_dat_flitpend    (_llcLogger_io_up_rx_dat_flitpend),
    .io_up_rx_dat_flitv       (_llcLogger_io_up_rx_dat_flitv),
    .io_up_rx_dat_flit        (_llcLogger_io_up_rx_dat_flit),
    .io_up_rx_dat_lcrdv       (_linkMonitor_1_io_out_rx_dat_lcrdv),
    .io_up_rx_snp_flitpend    (_llcLogger_io_up_rx_snp_flitpend),
    .io_up_rx_snp_flitv       (_llcLogger_io_up_rx_snp_flitv),
    .io_up_rx_snp_flit        (_llcLogger_io_up_rx_snp_flit),
    .io_up_rx_snp_lcrdv       (_linkMonitor_1_io_out_rx_snp_lcrdv),
    .io_down_txsactive        (_llcLogger_io_down_txsactive),
    .io_down_rxsactive        (_chi_openllc_opt_io_rn_0_rxsactive),
    .io_down_syscoreq         (_llcLogger_io_down_syscoreq),
    .io_down_syscoack         (_chi_openllc_opt_io_rn_0_syscoack),
    .io_down_tx_linkactivereq (_llcLogger_io_down_tx_linkactivereq),
    .io_down_tx_linkactiveack (_chi_openllc_opt_io_rn_0_tx_linkactiveack),
    .io_down_tx_req_flitpend  (_llcLogger_io_down_tx_req_flitpend),
    .io_down_tx_req_flitv     (_llcLogger_io_down_tx_req_flitv),
    .io_down_tx_req_flit      (_llcLogger_io_down_tx_req_flit),
    .io_down_tx_req_lcrdv     (_chi_openllc_opt_io_rn_0_tx_req_lcrdv),
    .io_down_tx_rsp_flitpend  (_llcLogger_io_down_tx_rsp_flitpend),
    .io_down_tx_rsp_flitv     (_llcLogger_io_down_tx_rsp_flitv),
    .io_down_tx_rsp_flit      (_llcLogger_io_down_tx_rsp_flit),
    .io_down_tx_rsp_lcrdv     (_chi_openllc_opt_io_rn_0_tx_rsp_lcrdv),
    .io_down_tx_dat_flitpend  (_llcLogger_io_down_tx_dat_flitpend),
    .io_down_tx_dat_flitv     (_llcLogger_io_down_tx_dat_flitv),
    .io_down_tx_dat_flit      (_llcLogger_io_down_tx_dat_flit),
    .io_down_tx_dat_lcrdv     (_chi_openllc_opt_io_rn_0_tx_dat_lcrdv),
    .io_down_rx_linkactivereq (_chi_openllc_opt_io_rn_0_rx_linkactivereq),
    .io_down_rx_linkactiveack (_llcLogger_io_down_rx_linkactiveack),
    .io_down_rx_rsp_flitpend  (_chi_openllc_opt_io_rn_0_rx_rsp_flitpend),
    .io_down_rx_rsp_flitv     (_chi_openllc_opt_io_rn_0_rx_rsp_flitv),
    .io_down_rx_rsp_flit      (_chi_openllc_opt_io_rn_0_rx_rsp_flit),
    .io_down_rx_rsp_lcrdv     (_llcLogger_io_down_rx_rsp_lcrdv),
    .io_down_rx_dat_flitpend  (_chi_openllc_opt_io_rn_0_rx_dat_flitpend),
    .io_down_rx_dat_flitv     (_chi_openllc_opt_io_rn_0_rx_dat_flitv),
    .io_down_rx_dat_flit      (_chi_openllc_opt_io_rn_0_rx_dat_flit),
    .io_down_rx_dat_lcrdv     (_llcLogger_io_down_rx_dat_lcrdv),
    .io_down_rx_snp_flitpend  (_chi_openllc_opt_io_rn_0_rx_snp_flitpend),
    .io_down_rx_snp_flitv     (_chi_openllc_opt_io_rn_0_rx_snp_flitv),
    .io_down_rx_snp_flit      (_chi_openllc_opt_io_rn_0_rx_snp_flit),
    .io_down_rx_snp_lcrdv     (_llcLogger_io_down_rx_snp_lcrdv)
  );
  ReceiverLinkMonitor linkMonitor (
    .clock                                (io_clock),
    .reset                                (io_reset),
    .io_in_txsactive                      (_core_with_l2_io_chi_txsactive),
    .io_in_rxsactive                      (_linkMonitor_io_in_rxsactive),
    .io_in_syscoreq                       (_core_with_l2_io_chi_syscoreq),
    .io_in_syscoack                       (_linkMonitor_io_in_syscoack),
    .io_in_tx_linkactivereq               (_core_with_l2_io_chi_tx_linkactivereq),
    .io_in_tx_linkactiveack               (_linkMonitor_io_in_tx_linkactiveack),
    .io_in_tx_req_flitpend                (_core_with_l2_io_chi_tx_req_flitpend),
    .io_in_tx_req_flitv                   (_core_with_l2_io_chi_tx_req_flitv),
    .io_in_tx_req_flit                    (_core_with_l2_io_chi_tx_req_flit),
    .io_in_tx_req_lcrdv                   (_linkMonitor_io_in_tx_req_lcrdv),
    .io_in_tx_rsp_flitpend                (_core_with_l2_io_chi_tx_rsp_flitpend),
    .io_in_tx_rsp_flitv                   (_core_with_l2_io_chi_tx_rsp_flitv),
    .io_in_tx_rsp_flit                    (_core_with_l2_io_chi_tx_rsp_flit),
    .io_in_tx_rsp_lcrdv                   (_linkMonitor_io_in_tx_rsp_lcrdv),
    .io_in_tx_dat_flitpend                (_core_with_l2_io_chi_tx_dat_flitpend),
    .io_in_tx_dat_flitv                   (_core_with_l2_io_chi_tx_dat_flitv),
    .io_in_tx_dat_flit                    (_core_with_l2_io_chi_tx_dat_flit),
    .io_in_tx_dat_lcrdv                   (_linkMonitor_io_in_tx_dat_lcrdv),
    .io_in_rx_linkactivereq               (_linkMonitor_io_in_rx_linkactivereq),
    .io_in_rx_linkactiveack               (_core_with_l2_io_chi_rx_linkactiveack),
    .io_in_rx_rsp_flitpend                (_linkMonitor_io_in_rx_rsp_flitpend),
    .io_in_rx_rsp_flitv                   (_linkMonitor_io_in_rx_rsp_flitv),
    .io_in_rx_rsp_flit                    (_linkMonitor_io_in_rx_rsp_flit),
    .io_in_rx_rsp_lcrdv                   (_core_with_l2_io_chi_rx_rsp_lcrdv),
    .io_in_rx_dat_flitpend                (_linkMonitor_io_in_rx_dat_flitpend),
    .io_in_rx_dat_flitv                   (_linkMonitor_io_in_rx_dat_flitv),
    .io_in_rx_dat_flit                    (_linkMonitor_io_in_rx_dat_flit),
    .io_in_rx_dat_lcrdv                   (_core_with_l2_io_chi_rx_dat_lcrdv),
    .io_in_rx_snp_flitpend                (_linkMonitor_io_in_rx_snp_flitpend),
    .io_in_rx_snp_flitv                   (_linkMonitor_io_in_rx_snp_flitv),
    .io_in_rx_snp_flit                    (_linkMonitor_io_in_rx_snp_flit),
    .io_in_rx_snp_lcrdv                   (_core_with_l2_io_chi_rx_snp_lcrdv),
    .io_out_tx_req_ready
      (|{_linkMonitor_1_io_in_tx_req_ready & outer_0_tx_req_valid,
         _linkMonitor_2_io_in_tx_req_ready & outer_1_tx_req_valid}),
    .io_out_tx_req_valid                  (_linkMonitor_io_out_tx_req_valid),
    .io_out_tx_req_bits_qos               (_linkMonitor_io_out_tx_req_bits_qos),
    .io_out_tx_req_bits_srcID             (_linkMonitor_io_out_tx_req_bits_srcID),
    .io_out_tx_req_bits_txnID             (_linkMonitor_io_out_tx_req_bits_txnID),
    .io_out_tx_req_bits_returnNID         (_linkMonitor_io_out_tx_req_bits_returnNID),
    .io_out_tx_req_bits_stashNIDValid     (_linkMonitor_io_out_tx_req_bits_stashNIDValid),
    .io_out_tx_req_bits_returnTxnID       (_linkMonitor_io_out_tx_req_bits_returnTxnID),
    .io_out_tx_req_bits_opcode            (_linkMonitor_io_out_tx_req_bits_opcode),
    .io_out_tx_req_bits_size              (_linkMonitor_io_out_tx_req_bits_size),
    .io_out_tx_req_bits_addr              (_linkMonitor_io_out_tx_req_bits_addr),
    .io_out_tx_req_bits_ns                (_linkMonitor_io_out_tx_req_bits_ns),
    .io_out_tx_req_bits_likelyshared      (_linkMonitor_io_out_tx_req_bits_likelyshared),
    .io_out_tx_req_bits_allowRetry        (_linkMonitor_io_out_tx_req_bits_allowRetry),
    .io_out_tx_req_bits_order             (_linkMonitor_io_out_tx_req_bits_order),
    .io_out_tx_req_bits_pCrdType          (_linkMonitor_io_out_tx_req_bits_pCrdType),
    .io_out_tx_req_bits_memAttr_allocate
      (_linkMonitor_io_out_tx_req_bits_memAttr_allocate),
    .io_out_tx_req_bits_memAttr_cacheable
      (_linkMonitor_io_out_tx_req_bits_memAttr_cacheable),
    .io_out_tx_req_bits_memAttr_device
      (_linkMonitor_io_out_tx_req_bits_memAttr_device),
    .io_out_tx_req_bits_memAttr_ewa       (_linkMonitor_io_out_tx_req_bits_memAttr_ewa),
    .io_out_tx_req_bits_snpAttr           (_linkMonitor_io_out_tx_req_bits_snpAttr),
    .io_out_tx_req_bits_lpIDWithPadding
      (_linkMonitor_io_out_tx_req_bits_lpIDWithPadding),
    .io_out_tx_req_bits_snoopMe           (_linkMonitor_io_out_tx_req_bits_snoopMe),
    .io_out_tx_req_bits_expCompAck        (_linkMonitor_io_out_tx_req_bits_expCompAck),
    .io_out_tx_req_bits_tagOp             (_linkMonitor_io_out_tx_req_bits_tagOp),
    .io_out_tx_req_bits_traceTag          (_linkMonitor_io_out_tx_req_bits_traceTag),
    .io_out_tx_req_bits_mpam_perfMonGroup
      (_linkMonitor_io_out_tx_req_bits_mpam_perfMonGroup),
    .io_out_tx_req_bits_mpam_partID       (_linkMonitor_io_out_tx_req_bits_mpam_partID),
    .io_out_tx_req_bits_mpam_mpamNS       (_linkMonitor_io_out_tx_req_bits_mpam_mpamNS),
    .io_out_tx_req_bits_rsvdc             (_linkMonitor_io_out_tx_req_bits_rsvdc),
    .io_out_tx_rsp_ready
      (|{_linkMonitor_1_io_in_tx_rsp_ready & outer_0_tx_rsp_valid,
         _linkMonitor_2_io_in_tx_rsp_ready & outer_1_tx_rsp_valid}),
    .io_out_tx_rsp_valid                  (_linkMonitor_io_out_tx_rsp_valid),
    .io_out_tx_rsp_bits_qos               (_linkMonitor_io_out_tx_rsp_bits_qos),
    .io_out_tx_rsp_bits_tgtID             (_linkMonitor_io_out_tx_rsp_bits_tgtID),
    .io_out_tx_rsp_bits_srcID             (_linkMonitor_io_out_tx_rsp_bits_srcID),
    .io_out_tx_rsp_bits_txnID             (_linkMonitor_io_out_tx_rsp_bits_txnID),
    .io_out_tx_rsp_bits_opcode            (_linkMonitor_io_out_tx_rsp_bits_opcode),
    .io_out_tx_rsp_bits_respErr           (_linkMonitor_io_out_tx_rsp_bits_respErr),
    .io_out_tx_rsp_bits_resp              (_linkMonitor_io_out_tx_rsp_bits_resp),
    .io_out_tx_rsp_bits_fwdState          (_linkMonitor_io_out_tx_rsp_bits_fwdState),
    .io_out_tx_rsp_bits_cBusy             (_linkMonitor_io_out_tx_rsp_bits_cBusy),
    .io_out_tx_rsp_bits_dbID              (_linkMonitor_io_out_tx_rsp_bits_dbID),
    .io_out_tx_rsp_bits_pCrdType          (_linkMonitor_io_out_tx_rsp_bits_pCrdType),
    .io_out_tx_rsp_bits_tagOp             (_linkMonitor_io_out_tx_rsp_bits_tagOp),
    .io_out_tx_rsp_bits_traceTag          (_linkMonitor_io_out_tx_rsp_bits_traceTag),
    .io_out_tx_dat_ready
      (|{_linkMonitor_1_io_in_tx_dat_ready & outer_0_tx_dat_valid,
         _linkMonitor_2_io_in_tx_dat_ready & outer_1_tx_dat_valid}),
    .io_out_tx_dat_valid                  (_linkMonitor_io_out_tx_dat_valid),
    .io_out_tx_dat_bits_qos               (_linkMonitor_io_out_tx_dat_bits_qos),
    .io_out_tx_dat_bits_tgtID             (_linkMonitor_io_out_tx_dat_bits_tgtID),
    .io_out_tx_dat_bits_srcID             (_linkMonitor_io_out_tx_dat_bits_srcID),
    .io_out_tx_dat_bits_txnID             (_linkMonitor_io_out_tx_dat_bits_txnID),
    .io_out_tx_dat_bits_homeNID           (_linkMonitor_io_out_tx_dat_bits_homeNID),
    .io_out_tx_dat_bits_opcode            (_linkMonitor_io_out_tx_dat_bits_opcode),
    .io_out_tx_dat_bits_respErr           (_linkMonitor_io_out_tx_dat_bits_respErr),
    .io_out_tx_dat_bits_resp              (_linkMonitor_io_out_tx_dat_bits_resp),
    .io_out_tx_dat_bits_dataSource        (_linkMonitor_io_out_tx_dat_bits_dataSource),
    .io_out_tx_dat_bits_cBusy             (_linkMonitor_io_out_tx_dat_bits_cBusy),
    .io_out_tx_dat_bits_dbID              (_linkMonitor_io_out_tx_dat_bits_dbID),
    .io_out_tx_dat_bits_ccID              (_linkMonitor_io_out_tx_dat_bits_ccID),
    .io_out_tx_dat_bits_dataID            (_linkMonitor_io_out_tx_dat_bits_dataID),
    .io_out_tx_dat_bits_tagOp             (_linkMonitor_io_out_tx_dat_bits_tagOp),
    .io_out_tx_dat_bits_tag               (_linkMonitor_io_out_tx_dat_bits_tag),
    .io_out_tx_dat_bits_tu                (_linkMonitor_io_out_tx_dat_bits_tu),
    .io_out_tx_dat_bits_traceTag          (_linkMonitor_io_out_tx_dat_bits_traceTag),
    .io_out_tx_dat_bits_rsvdc             (_linkMonitor_io_out_tx_dat_bits_rsvdc),
    .io_out_tx_dat_bits_be                (_linkMonitor_io_out_tx_dat_bits_be),
    .io_out_tx_dat_bits_data              (_linkMonitor_io_out_tx_dat_bits_data),
    .io_out_tx_dat_bits_dataCheck         (_linkMonitor_io_out_tx_dat_bits_dataCheck),
    .io_out_tx_dat_bits_poison            (_linkMonitor_io_out_tx_dat_bits_poison),
    .io_out_rx_rsp_ready                  (_linkMonitor_io_out_rx_rsp_ready),
    .io_out_rx_rsp_valid                  (_rxrspArb_io_out_valid),
    .io_out_rx_rsp_bits_qos               (_rxrspArb_io_out_bits_qos),
    .io_out_rx_rsp_bits_tgtID             (_rxrspArb_io_out_bits_tgtID),
    .io_out_rx_rsp_bits_srcID             (_rxrspArb_io_out_bits_srcID),
    .io_out_rx_rsp_bits_txnID             (_rxrspArb_io_out_bits_txnID),
    .io_out_rx_rsp_bits_opcode            (_rxrspArb_io_out_bits_opcode),
    .io_out_rx_rsp_bits_respErr           (_rxrspArb_io_out_bits_respErr),
    .io_out_rx_rsp_bits_resp              (_rxrspArb_io_out_bits_resp),
    .io_out_rx_rsp_bits_fwdState          (_rxrspArb_io_out_bits_fwdState),
    .io_out_rx_rsp_bits_cBusy             (_rxrspArb_io_out_bits_cBusy),
    .io_out_rx_rsp_bits_dbID              (_rxrspArb_io_out_bits_dbID),
    .io_out_rx_rsp_bits_pCrdType          (_rxrspArb_io_out_bits_pCrdType),
    .io_out_rx_rsp_bits_tagOp             (_rxrspArb_io_out_bits_tagOp),
    .io_out_rx_rsp_bits_traceTag          (_rxrspArb_io_out_bits_traceTag),
    .io_out_rx_dat_ready                  (_linkMonitor_io_out_rx_dat_ready),
    .io_out_rx_dat_valid                  (_rxdatArb_io_out_valid),
    .io_out_rx_dat_bits_qos               (_rxdatArb_io_out_bits_qos),
    .io_out_rx_dat_bits_tgtID             (_rxdatArb_io_out_bits_tgtID),
    .io_out_rx_dat_bits_srcID             (_rxdatArb_io_out_bits_srcID),
    .io_out_rx_dat_bits_txnID             (_rxdatArb_io_out_bits_txnID),
    .io_out_rx_dat_bits_homeNID           (_rxdatArb_io_out_bits_homeNID),
    .io_out_rx_dat_bits_opcode            (_rxdatArb_io_out_bits_opcode),
    .io_out_rx_dat_bits_respErr           (_rxdatArb_io_out_bits_respErr),
    .io_out_rx_dat_bits_resp              (_rxdatArb_io_out_bits_resp),
    .io_out_rx_dat_bits_dataSource        (_rxdatArb_io_out_bits_dataSource),
    .io_out_rx_dat_bits_cBusy             (_rxdatArb_io_out_bits_cBusy),
    .io_out_rx_dat_bits_dbID              (_rxdatArb_io_out_bits_dbID),
    .io_out_rx_dat_bits_ccID              (_rxdatArb_io_out_bits_ccID),
    .io_out_rx_dat_bits_dataID            (_rxdatArb_io_out_bits_dataID),
    .io_out_rx_dat_bits_tagOp             (_rxdatArb_io_out_bits_tagOp),
    .io_out_rx_dat_bits_tag               (_rxdatArb_io_out_bits_tag),
    .io_out_rx_dat_bits_tu                (_rxdatArb_io_out_bits_tu),
    .io_out_rx_dat_bits_traceTag          (_rxdatArb_io_out_bits_traceTag),
    .io_out_rx_dat_bits_rsvdc             (_rxdatArb_io_out_bits_rsvdc),
    .io_out_rx_dat_bits_be                (_rxdatArb_io_out_bits_be),
    .io_out_rx_dat_bits_data              (_rxdatArb_io_out_bits_data),
    .io_out_rx_dat_bits_dataCheck         (_rxdatArb_io_out_bits_dataCheck),
    .io_out_rx_dat_bits_poison            (_rxdatArb_io_out_bits_poison),
    .io_out_rx_snp_ready                  (_linkMonitor_io_out_rx_snp_ready),
    .io_out_rx_snp_valid                  (_rxsnpArb_io_out_valid),
    .io_out_rx_snp_bits_qos               (_rxsnpArb_io_out_bits_qos),
    .io_out_rx_snp_bits_srcID             (_rxsnpArb_io_out_bits_srcID),
    .io_out_rx_snp_bits_txnID             (_rxsnpArb_io_out_bits_txnID),
    .io_out_rx_snp_bits_fwdNID            (_rxsnpArb_io_out_bits_fwdNID),
    .io_out_rx_snp_bits_fwdTxnID          (_rxsnpArb_io_out_bits_fwdTxnID),
    .io_out_rx_snp_bits_opcode            (_rxsnpArb_io_out_bits_opcode),
    .io_out_rx_snp_bits_addr              (_rxsnpArb_io_out_bits_addr),
    .io_out_rx_snp_bits_ns                (_rxsnpArb_io_out_bits_ns),
    .io_out_rx_snp_bits_doNotGoToSD       (_rxsnpArb_io_out_bits_doNotGoToSD),
    .io_out_rx_snp_bits_retToSrc          (_rxsnpArb_io_out_bits_retToSrc),
    .io_out_rx_snp_bits_traceTag          (_rxsnpArb_io_out_bits_traceTag),
    .io_out_rx_snp_bits_mpam_perfMonGroup (_rxsnpArb_io_out_bits_mpam_perfMonGroup),
    .io_out_rx_snp_bits_mpam_partID       (_rxsnpArb_io_out_bits_mpam_partID),
    .io_out_rx_snp_bits_mpam_mpamNS       (_rxsnpArb_io_out_bits_mpam_mpamNS)
  );
  FastArbiter_117 rxsnpArb (
    .clock                          (io_clock),
    .reset                          (io_reset),
    .io_in_0_valid                  (_linkMonitor_1_io_in_rx_snp_valid),
    .io_in_0_bits_qos               (_linkMonitor_1_io_in_rx_snp_bits_qos),
    .io_in_0_bits_srcID             (_linkMonitor_1_io_in_rx_snp_bits_srcID),
    .io_in_0_bits_txnID             (_linkMonitor_1_io_in_rx_snp_bits_txnID),
    .io_in_0_bits_fwdNID            (_linkMonitor_1_io_in_rx_snp_bits_fwdNID),
    .io_in_0_bits_fwdTxnID          (_linkMonitor_1_io_in_rx_snp_bits_fwdTxnID),
    .io_in_0_bits_opcode            (_linkMonitor_1_io_in_rx_snp_bits_opcode),
    .io_in_0_bits_addr              (_linkMonitor_1_io_in_rx_snp_bits_addr),
    .io_in_0_bits_ns                (_linkMonitor_1_io_in_rx_snp_bits_ns),
    .io_in_0_bits_doNotGoToSD       (_linkMonitor_1_io_in_rx_snp_bits_doNotGoToSD),
    .io_in_0_bits_retToSrc          (_linkMonitor_1_io_in_rx_snp_bits_retToSrc),
    .io_in_0_bits_traceTag          (_linkMonitor_1_io_in_rx_snp_bits_traceTag),
    .io_in_0_bits_mpam_perfMonGroup (_linkMonitor_1_io_in_rx_snp_bits_mpam_perfMonGroup),
    .io_in_0_bits_mpam_partID       (_linkMonitor_1_io_in_rx_snp_bits_mpam_partID),
    .io_in_0_bits_mpam_mpamNS       (_linkMonitor_1_io_in_rx_snp_bits_mpam_mpamNS),
    .io_in_1_valid                  (_linkMonitor_2_io_in_rx_snp_valid),
    .io_in_1_bits_qos               (_linkMonitor_2_io_in_rx_snp_bits_qos),
    .io_in_1_bits_srcID             (_linkMonitor_2_io_in_rx_snp_bits_srcID),
    .io_in_1_bits_txnID             (_linkMonitor_2_io_in_rx_snp_bits_txnID),
    .io_in_1_bits_fwdNID            (_linkMonitor_2_io_in_rx_snp_bits_fwdNID),
    .io_in_1_bits_fwdTxnID          (_linkMonitor_2_io_in_rx_snp_bits_fwdTxnID),
    .io_in_1_bits_opcode            (_linkMonitor_2_io_in_rx_snp_bits_opcode),
    .io_in_1_bits_addr              (_linkMonitor_2_io_in_rx_snp_bits_addr),
    .io_in_1_bits_ns                (_linkMonitor_2_io_in_rx_snp_bits_ns),
    .io_in_1_bits_doNotGoToSD       (_linkMonitor_2_io_in_rx_snp_bits_doNotGoToSD),
    .io_in_1_bits_retToSrc          (_linkMonitor_2_io_in_rx_snp_bits_retToSrc),
    .io_in_1_bits_traceTag          (_linkMonitor_2_io_in_rx_snp_bits_traceTag),
    .io_in_1_bits_mpam_perfMonGroup (_linkMonitor_2_io_in_rx_snp_bits_mpam_perfMonGroup),
    .io_in_1_bits_mpam_partID       (_linkMonitor_2_io_in_rx_snp_bits_mpam_partID),
    .io_in_1_bits_mpam_mpamNS       (_linkMonitor_2_io_in_rx_snp_bits_mpam_mpamNS),
    .io_out_ready                   (_linkMonitor_io_out_rx_snp_ready),
    .io_out_valid                   (_rxsnpArb_io_out_valid),
    .io_out_bits_qos                (_rxsnpArb_io_out_bits_qos),
    .io_out_bits_srcID              (_rxsnpArb_io_out_bits_srcID),
    .io_out_bits_txnID              (_rxsnpArb_io_out_bits_txnID),
    .io_out_bits_fwdNID             (_rxsnpArb_io_out_bits_fwdNID),
    .io_out_bits_fwdTxnID           (_rxsnpArb_io_out_bits_fwdTxnID),
    .io_out_bits_opcode             (_rxsnpArb_io_out_bits_opcode),
    .io_out_bits_addr               (_rxsnpArb_io_out_bits_addr),
    .io_out_bits_ns                 (_rxsnpArb_io_out_bits_ns),
    .io_out_bits_doNotGoToSD        (_rxsnpArb_io_out_bits_doNotGoToSD),
    .io_out_bits_retToSrc           (_rxsnpArb_io_out_bits_retToSrc),
    .io_out_bits_traceTag           (_rxsnpArb_io_out_bits_traceTag),
    .io_out_bits_mpam_perfMonGroup  (_rxsnpArb_io_out_bits_mpam_perfMonGroup),
    .io_out_bits_mpam_partID        (_rxsnpArb_io_out_bits_mpam_partID),
    .io_out_bits_mpam_mpamNS        (_rxsnpArb_io_out_bits_mpam_mpamNS),
    .io_chosen                      (_rxsnpArb_io_chosen)
  );
  FastArbiter_118 rxrspArb (
    .clock                 (io_clock),
    .reset                 (io_reset),
    .io_in_0_valid         (_linkMonitor_1_io_in_rx_rsp_valid),
    .io_in_0_bits_qos      (_linkMonitor_1_io_in_rx_rsp_bits_qos),
    .io_in_0_bits_tgtID    (_linkMonitor_1_io_in_rx_rsp_bits_tgtID),
    .io_in_0_bits_srcID    (_linkMonitor_1_io_in_rx_rsp_bits_srcID),
    .io_in_0_bits_txnID    (_linkMonitor_1_io_in_rx_rsp_bits_txnID),
    .io_in_0_bits_opcode   (_linkMonitor_1_io_in_rx_rsp_bits_opcode),
    .io_in_0_bits_respErr  (_linkMonitor_1_io_in_rx_rsp_bits_respErr),
    .io_in_0_bits_resp     (_linkMonitor_1_io_in_rx_rsp_bits_resp),
    .io_in_0_bits_fwdState (_linkMonitor_1_io_in_rx_rsp_bits_fwdState),
    .io_in_0_bits_cBusy    (_linkMonitor_1_io_in_rx_rsp_bits_cBusy),
    .io_in_0_bits_dbID     (_linkMonitor_1_io_in_rx_rsp_bits_dbID),
    .io_in_0_bits_pCrdType (_linkMonitor_1_io_in_rx_rsp_bits_pCrdType),
    .io_in_0_bits_tagOp    (_linkMonitor_1_io_in_rx_rsp_bits_tagOp),
    .io_in_0_bits_traceTag (_linkMonitor_1_io_in_rx_rsp_bits_traceTag),
    .io_in_1_valid         (_linkMonitor_2_io_in_rx_rsp_valid),
    .io_in_1_bits_qos      (_linkMonitor_2_io_in_rx_rsp_bits_qos),
    .io_in_1_bits_tgtID    (_linkMonitor_2_io_in_rx_rsp_bits_tgtID),
    .io_in_1_bits_srcID    (_linkMonitor_2_io_in_rx_rsp_bits_srcID),
    .io_in_1_bits_txnID    (_linkMonitor_2_io_in_rx_rsp_bits_txnID),
    .io_in_1_bits_opcode   (_linkMonitor_2_io_in_rx_rsp_bits_opcode),
    .io_in_1_bits_respErr  (_linkMonitor_2_io_in_rx_rsp_bits_respErr),
    .io_in_1_bits_resp     (_linkMonitor_2_io_in_rx_rsp_bits_resp),
    .io_in_1_bits_fwdState (_linkMonitor_2_io_in_rx_rsp_bits_fwdState),
    .io_in_1_bits_cBusy    (_linkMonitor_2_io_in_rx_rsp_bits_cBusy),
    .io_in_1_bits_dbID     (_linkMonitor_2_io_in_rx_rsp_bits_dbID),
    .io_in_1_bits_pCrdType (_linkMonitor_2_io_in_rx_rsp_bits_pCrdType),
    .io_in_1_bits_tagOp    (_linkMonitor_2_io_in_rx_rsp_bits_tagOp),
    .io_in_1_bits_traceTag (_linkMonitor_2_io_in_rx_rsp_bits_traceTag),
    .io_out_ready          (_linkMonitor_io_out_rx_rsp_ready),
    .io_out_valid          (_rxrspArb_io_out_valid),
    .io_out_bits_qos       (_rxrspArb_io_out_bits_qos),
    .io_out_bits_tgtID     (_rxrspArb_io_out_bits_tgtID),
    .io_out_bits_srcID     (_rxrspArb_io_out_bits_srcID),
    .io_out_bits_txnID     (_rxrspArb_io_out_bits_txnID),
    .io_out_bits_opcode    (_rxrspArb_io_out_bits_opcode),
    .io_out_bits_respErr   (_rxrspArb_io_out_bits_respErr),
    .io_out_bits_resp      (_rxrspArb_io_out_bits_resp),
    .io_out_bits_fwdState  (_rxrspArb_io_out_bits_fwdState),
    .io_out_bits_cBusy     (_rxrspArb_io_out_bits_cBusy),
    .io_out_bits_dbID      (_rxrspArb_io_out_bits_dbID),
    .io_out_bits_pCrdType  (_rxrspArb_io_out_bits_pCrdType),
    .io_out_bits_tagOp     (_rxrspArb_io_out_bits_tagOp),
    .io_out_bits_traceTag  (_rxrspArb_io_out_bits_traceTag),
    .io_chosen             (_rxrspArb_io_chosen)
  );
  FastArbiter_119 rxdatArb (
    .clock                   (io_clock),
    .reset                   (io_reset),
    .io_in_0_valid           (_linkMonitor_1_io_in_rx_dat_valid),
    .io_in_0_bits_qos        (_linkMonitor_1_io_in_rx_dat_bits_qos),
    .io_in_0_bits_tgtID      (_linkMonitor_1_io_in_rx_dat_bits_tgtID),
    .io_in_0_bits_srcID      (_linkMonitor_1_io_in_rx_dat_bits_srcID),
    .io_in_0_bits_txnID      (_linkMonitor_1_io_in_rx_dat_bits_txnID),
    .io_in_0_bits_homeNID    (_linkMonitor_1_io_in_rx_dat_bits_homeNID),
    .io_in_0_bits_opcode     (_linkMonitor_1_io_in_rx_dat_bits_opcode),
    .io_in_0_bits_respErr    (_linkMonitor_1_io_in_rx_dat_bits_respErr),
    .io_in_0_bits_resp       (_linkMonitor_1_io_in_rx_dat_bits_resp),
    .io_in_0_bits_dataSource (_linkMonitor_1_io_in_rx_dat_bits_dataSource),
    .io_in_0_bits_cBusy      (_linkMonitor_1_io_in_rx_dat_bits_cBusy),
    .io_in_0_bits_dbID       (_linkMonitor_1_io_in_rx_dat_bits_dbID),
    .io_in_0_bits_ccID       (_linkMonitor_1_io_in_rx_dat_bits_ccID),
    .io_in_0_bits_dataID     (_linkMonitor_1_io_in_rx_dat_bits_dataID),
    .io_in_0_bits_tagOp      (_linkMonitor_1_io_in_rx_dat_bits_tagOp),
    .io_in_0_bits_tag        (_linkMonitor_1_io_in_rx_dat_bits_tag),
    .io_in_0_bits_tu         (_linkMonitor_1_io_in_rx_dat_bits_tu),
    .io_in_0_bits_traceTag   (_linkMonitor_1_io_in_rx_dat_bits_traceTag),
    .io_in_0_bits_rsvdc      (_linkMonitor_1_io_in_rx_dat_bits_rsvdc),
    .io_in_0_bits_be         (_linkMonitor_1_io_in_rx_dat_bits_be),
    .io_in_0_bits_data       (_linkMonitor_1_io_in_rx_dat_bits_data),
    .io_in_0_bits_dataCheck  (_linkMonitor_1_io_in_rx_dat_bits_dataCheck),
    .io_in_0_bits_poison     (_linkMonitor_1_io_in_rx_dat_bits_poison),
    .io_in_1_valid           (_linkMonitor_2_io_in_rx_dat_valid),
    .io_in_1_bits_qos        (_linkMonitor_2_io_in_rx_dat_bits_qos),
    .io_in_1_bits_tgtID      (_linkMonitor_2_io_in_rx_dat_bits_tgtID),
    .io_in_1_bits_srcID      (_linkMonitor_2_io_in_rx_dat_bits_srcID),
    .io_in_1_bits_txnID      (_linkMonitor_2_io_in_rx_dat_bits_txnID),
    .io_in_1_bits_homeNID    (_linkMonitor_2_io_in_rx_dat_bits_homeNID),
    .io_in_1_bits_opcode     (_linkMonitor_2_io_in_rx_dat_bits_opcode),
    .io_in_1_bits_respErr    (_linkMonitor_2_io_in_rx_dat_bits_respErr),
    .io_in_1_bits_resp       (_linkMonitor_2_io_in_rx_dat_bits_resp),
    .io_in_1_bits_dataSource (_linkMonitor_2_io_in_rx_dat_bits_dataSource),
    .io_in_1_bits_cBusy      (_linkMonitor_2_io_in_rx_dat_bits_cBusy),
    .io_in_1_bits_dbID       (_linkMonitor_2_io_in_rx_dat_bits_dbID),
    .io_in_1_bits_ccID       (_linkMonitor_2_io_in_rx_dat_bits_ccID),
    .io_in_1_bits_dataID     (_linkMonitor_2_io_in_rx_dat_bits_dataID),
    .io_in_1_bits_tagOp      (_linkMonitor_2_io_in_rx_dat_bits_tagOp),
    .io_in_1_bits_tag        (_linkMonitor_2_io_in_rx_dat_bits_tag),
    .io_in_1_bits_tu         (_linkMonitor_2_io_in_rx_dat_bits_tu),
    .io_in_1_bits_traceTag   (_linkMonitor_2_io_in_rx_dat_bits_traceTag),
    .io_in_1_bits_rsvdc      (_linkMonitor_2_io_in_rx_dat_bits_rsvdc),
    .io_in_1_bits_be         (_linkMonitor_2_io_in_rx_dat_bits_be),
    .io_in_1_bits_data       (_linkMonitor_2_io_in_rx_dat_bits_data),
    .io_in_1_bits_dataCheck  (_linkMonitor_2_io_in_rx_dat_bits_dataCheck),
    .io_in_1_bits_poison     (_linkMonitor_2_io_in_rx_dat_bits_poison),
    .io_out_ready            (_linkMonitor_io_out_rx_dat_ready),
    .io_out_valid            (_rxdatArb_io_out_valid),
    .io_out_bits_qos         (_rxdatArb_io_out_bits_qos),
    .io_out_bits_tgtID       (_rxdatArb_io_out_bits_tgtID),
    .io_out_bits_srcID       (_rxdatArb_io_out_bits_srcID),
    .io_out_bits_txnID       (_rxdatArb_io_out_bits_txnID),
    .io_out_bits_homeNID     (_rxdatArb_io_out_bits_homeNID),
    .io_out_bits_opcode      (_rxdatArb_io_out_bits_opcode),
    .io_out_bits_respErr     (_rxdatArb_io_out_bits_respErr),
    .io_out_bits_resp        (_rxdatArb_io_out_bits_resp),
    .io_out_bits_dataSource  (_rxdatArb_io_out_bits_dataSource),
    .io_out_bits_cBusy       (_rxdatArb_io_out_bits_cBusy),
    .io_out_bits_dbID        (_rxdatArb_io_out_bits_dbID),
    .io_out_bits_ccID        (_rxdatArb_io_out_bits_ccID),
    .io_out_bits_dataID      (_rxdatArb_io_out_bits_dataID),
    .io_out_bits_tagOp       (_rxdatArb_io_out_bits_tagOp),
    .io_out_bits_tag         (_rxdatArb_io_out_bits_tag),
    .io_out_bits_tu          (_rxdatArb_io_out_bits_tu),
    .io_out_bits_traceTag    (_rxdatArb_io_out_bits_traceTag),
    .io_out_bits_rsvdc       (_rxdatArb_io_out_bits_rsvdc),
    .io_out_bits_be          (_rxdatArb_io_out_bits_be),
    .io_out_bits_data        (_rxdatArb_io_out_bits_data),
    .io_out_bits_dataCheck   (_rxdatArb_io_out_bits_dataCheck),
    .io_out_bits_poison      (_rxdatArb_io_out_bits_poison),
    .io_chosen               (_rxdatArb_io_chosen)
  );
  TransmitterLinkMonitor linkMonitor_1 (
    .clock                               (io_clock),
    .reset                               (io_reset),
    .io_in_tx_req_ready                  (_linkMonitor_1_io_in_tx_req_ready),
    .io_in_tx_req_valid                  (outer_0_tx_req_valid),
    .io_in_tx_req_bits_qos               (_linkMonitor_io_out_tx_req_bits_qos),
    .io_in_tx_req_bits_tgtID             (linkMonitor_2_io_in_tx_req_bits_tgtID),
    .io_in_tx_req_bits_srcID             (_linkMonitor_io_out_tx_req_bits_srcID),
    .io_in_tx_req_bits_txnID             (_linkMonitor_io_out_tx_req_bits_txnID),
    .io_in_tx_req_bits_returnNID         (_linkMonitor_io_out_tx_req_bits_returnNID),
    .io_in_tx_req_bits_stashNIDValid     (_linkMonitor_io_out_tx_req_bits_stashNIDValid),
    .io_in_tx_req_bits_returnTxnID       (_linkMonitor_io_out_tx_req_bits_returnTxnID),
    .io_in_tx_req_bits_opcode            (_linkMonitor_io_out_tx_req_bits_opcode),
    .io_in_tx_req_bits_size              (_linkMonitor_io_out_tx_req_bits_size),
    .io_in_tx_req_bits_addr              (_linkMonitor_io_out_tx_req_bits_addr),
    .io_in_tx_req_bits_ns                (_linkMonitor_io_out_tx_req_bits_ns),
    .io_in_tx_req_bits_likelyshared      (_linkMonitor_io_out_tx_req_bits_likelyshared),
    .io_in_tx_req_bits_allowRetry        (_linkMonitor_io_out_tx_req_bits_allowRetry),
    .io_in_tx_req_bits_order             (_linkMonitor_io_out_tx_req_bits_order),
    .io_in_tx_req_bits_pCrdType          (_linkMonitor_io_out_tx_req_bits_pCrdType),
    .io_in_tx_req_bits_memAttr_allocate
      (_linkMonitor_io_out_tx_req_bits_memAttr_allocate),
    .io_in_tx_req_bits_memAttr_cacheable
      (_linkMonitor_io_out_tx_req_bits_memAttr_cacheable),
    .io_in_tx_req_bits_memAttr_device    (_linkMonitor_io_out_tx_req_bits_memAttr_device),
    .io_in_tx_req_bits_memAttr_ewa       (_linkMonitor_io_out_tx_req_bits_memAttr_ewa),
    .io_in_tx_req_bits_snpAttr           (_linkMonitor_io_out_tx_req_bits_snpAttr),
    .io_in_tx_req_bits_lpIDWithPadding
      (_linkMonitor_io_out_tx_req_bits_lpIDWithPadding),
    .io_in_tx_req_bits_snoopMe           (_linkMonitor_io_out_tx_req_bits_snoopMe),
    .io_in_tx_req_bits_expCompAck        (_linkMonitor_io_out_tx_req_bits_expCompAck),
    .io_in_tx_req_bits_tagOp             (_linkMonitor_io_out_tx_req_bits_tagOp),
    .io_in_tx_req_bits_traceTag          (_linkMonitor_io_out_tx_req_bits_traceTag),
    .io_in_tx_req_bits_mpam_perfMonGroup
      (_linkMonitor_io_out_tx_req_bits_mpam_perfMonGroup),
    .io_in_tx_req_bits_mpam_partID       (_linkMonitor_io_out_tx_req_bits_mpam_partID),
    .io_in_tx_req_bits_mpam_mpamNS       (_linkMonitor_io_out_tx_req_bits_mpam_mpamNS),
    .io_in_tx_req_bits_rsvdc             (_linkMonitor_io_out_tx_req_bits_rsvdc),
    .io_in_tx_rsp_ready                  (_linkMonitor_1_io_in_tx_rsp_ready),
    .io_in_tx_rsp_valid                  (outer_0_tx_rsp_valid),
    .io_in_tx_rsp_bits_qos               (_linkMonitor_io_out_tx_rsp_bits_qos),
    .io_in_tx_rsp_bits_tgtID             (_linkMonitor_io_out_tx_rsp_bits_tgtID),
    .io_in_tx_rsp_bits_srcID             (_linkMonitor_io_out_tx_rsp_bits_srcID),
    .io_in_tx_rsp_bits_txnID             (_linkMonitor_io_out_tx_rsp_bits_txnID),
    .io_in_tx_rsp_bits_opcode            (_linkMonitor_io_out_tx_rsp_bits_opcode),
    .io_in_tx_rsp_bits_respErr           (_linkMonitor_io_out_tx_rsp_bits_respErr),
    .io_in_tx_rsp_bits_resp              (_linkMonitor_io_out_tx_rsp_bits_resp),
    .io_in_tx_rsp_bits_fwdState          (_linkMonitor_io_out_tx_rsp_bits_fwdState),
    .io_in_tx_rsp_bits_cBusy             (_linkMonitor_io_out_tx_rsp_bits_cBusy),
    .io_in_tx_rsp_bits_dbID              (_linkMonitor_io_out_tx_rsp_bits_dbID),
    .io_in_tx_rsp_bits_pCrdType          (_linkMonitor_io_out_tx_rsp_bits_pCrdType),
    .io_in_tx_rsp_bits_tagOp             (_linkMonitor_io_out_tx_rsp_bits_tagOp),
    .io_in_tx_rsp_bits_traceTag          (_linkMonitor_io_out_tx_rsp_bits_traceTag),
    .io_in_tx_dat_ready                  (_linkMonitor_1_io_in_tx_dat_ready),
    .io_in_tx_dat_valid                  (outer_0_tx_dat_valid),
    .io_in_tx_dat_bits_qos               (_linkMonitor_io_out_tx_dat_bits_qos),
    .io_in_tx_dat_bits_tgtID             (_linkMonitor_io_out_tx_dat_bits_tgtID),
    .io_in_tx_dat_bits_srcID             (_linkMonitor_io_out_tx_dat_bits_srcID),
    .io_in_tx_dat_bits_txnID             (_linkMonitor_io_out_tx_dat_bits_txnID),
    .io_in_tx_dat_bits_homeNID           (_linkMonitor_io_out_tx_dat_bits_homeNID),
    .io_in_tx_dat_bits_opcode            (_linkMonitor_io_out_tx_dat_bits_opcode),
    .io_in_tx_dat_bits_respErr           (_linkMonitor_io_out_tx_dat_bits_respErr),
    .io_in_tx_dat_bits_resp              (_linkMonitor_io_out_tx_dat_bits_resp),
    .io_in_tx_dat_bits_dataSource        (_linkMonitor_io_out_tx_dat_bits_dataSource),
    .io_in_tx_dat_bits_cBusy             (_linkMonitor_io_out_tx_dat_bits_cBusy),
    .io_in_tx_dat_bits_dbID              (_linkMonitor_io_out_tx_dat_bits_dbID),
    .io_in_tx_dat_bits_ccID              (_linkMonitor_io_out_tx_dat_bits_ccID),
    .io_in_tx_dat_bits_dataID            (_linkMonitor_io_out_tx_dat_bits_dataID),
    .io_in_tx_dat_bits_tagOp             (_linkMonitor_io_out_tx_dat_bits_tagOp),
    .io_in_tx_dat_bits_tag               (_linkMonitor_io_out_tx_dat_bits_tag),
    .io_in_tx_dat_bits_tu                (_linkMonitor_io_out_tx_dat_bits_tu),
    .io_in_tx_dat_bits_traceTag          (_linkMonitor_io_out_tx_dat_bits_traceTag),
    .io_in_tx_dat_bits_rsvdc             (_linkMonitor_io_out_tx_dat_bits_rsvdc),
    .io_in_tx_dat_bits_be                (_linkMonitor_io_out_tx_dat_bits_be),
    .io_in_tx_dat_bits_data              (_linkMonitor_io_out_tx_dat_bits_data),
    .io_in_tx_dat_bits_dataCheck         (_linkMonitor_io_out_tx_dat_bits_dataCheck),
    .io_in_tx_dat_bits_poison            (_linkMonitor_io_out_tx_dat_bits_poison),
    .io_in_rx_rsp_ready                  (_outer_1_rx_rsp_ready_T & ~_rxrspArb_io_chosen),
    .io_in_rx_rsp_valid                  (_linkMonitor_1_io_in_rx_rsp_valid),
    .io_in_rx_rsp_bits_qos               (_linkMonitor_1_io_in_rx_rsp_bits_qos),
    .io_in_rx_rsp_bits_tgtID             (_linkMonitor_1_io_in_rx_rsp_bits_tgtID),
    .io_in_rx_rsp_bits_srcID             (_linkMonitor_1_io_in_rx_rsp_bits_srcID),
    .io_in_rx_rsp_bits_txnID             (_linkMonitor_1_io_in_rx_rsp_bits_txnID),
    .io_in_rx_rsp_bits_opcode            (_linkMonitor_1_io_in_rx_rsp_bits_opcode),
    .io_in_rx_rsp_bits_respErr           (_linkMonitor_1_io_in_rx_rsp_bits_respErr),
    .io_in_rx_rsp_bits_resp              (_linkMonitor_1_io_in_rx_rsp_bits_resp),
    .io_in_rx_rsp_bits_fwdState          (_linkMonitor_1_io_in_rx_rsp_bits_fwdState),
    .io_in_rx_rsp_bits_cBusy             (_linkMonitor_1_io_in_rx_rsp_bits_cBusy),
    .io_in_rx_rsp_bits_dbID              (_linkMonitor_1_io_in_rx_rsp_bits_dbID),
    .io_in_rx_rsp_bits_pCrdType          (_linkMonitor_1_io_in_rx_rsp_bits_pCrdType),
    .io_in_rx_rsp_bits_tagOp             (_linkMonitor_1_io_in_rx_rsp_bits_tagOp),
    .io_in_rx_rsp_bits_traceTag          (_linkMonitor_1_io_in_rx_rsp_bits_traceTag),
    .io_in_rx_dat_ready                  (_outer_1_rx_dat_ready_T & ~_rxdatArb_io_chosen),
    .io_in_rx_dat_valid                  (_linkMonitor_1_io_in_rx_dat_valid),
    .io_in_rx_dat_bits_qos               (_linkMonitor_1_io_in_rx_dat_bits_qos),
    .io_in_rx_dat_bits_tgtID             (_linkMonitor_1_io_in_rx_dat_bits_tgtID),
    .io_in_rx_dat_bits_srcID             (_linkMonitor_1_io_in_rx_dat_bits_srcID),
    .io_in_rx_dat_bits_txnID             (_linkMonitor_1_io_in_rx_dat_bits_txnID),
    .io_in_rx_dat_bits_homeNID           (_linkMonitor_1_io_in_rx_dat_bits_homeNID),
    .io_in_rx_dat_bits_opcode            (_linkMonitor_1_io_in_rx_dat_bits_opcode),
    .io_in_rx_dat_bits_respErr           (_linkMonitor_1_io_in_rx_dat_bits_respErr),
    .io_in_rx_dat_bits_resp              (_linkMonitor_1_io_in_rx_dat_bits_resp),
    .io_in_rx_dat_bits_dataSource        (_linkMonitor_1_io_in_rx_dat_bits_dataSource),
    .io_in_rx_dat_bits_cBusy             (_linkMonitor_1_io_in_rx_dat_bits_cBusy),
    .io_in_rx_dat_bits_dbID              (_linkMonitor_1_io_in_rx_dat_bits_dbID),
    .io_in_rx_dat_bits_ccID              (_linkMonitor_1_io_in_rx_dat_bits_ccID),
    .io_in_rx_dat_bits_dataID            (_linkMonitor_1_io_in_rx_dat_bits_dataID),
    .io_in_rx_dat_bits_tagOp             (_linkMonitor_1_io_in_rx_dat_bits_tagOp),
    .io_in_rx_dat_bits_tag               (_linkMonitor_1_io_in_rx_dat_bits_tag),
    .io_in_rx_dat_bits_tu                (_linkMonitor_1_io_in_rx_dat_bits_tu),
    .io_in_rx_dat_bits_traceTag          (_linkMonitor_1_io_in_rx_dat_bits_traceTag),
    .io_in_rx_dat_bits_rsvdc             (_linkMonitor_1_io_in_rx_dat_bits_rsvdc),
    .io_in_rx_dat_bits_be                (_linkMonitor_1_io_in_rx_dat_bits_be),
    .io_in_rx_dat_bits_data              (_linkMonitor_1_io_in_rx_dat_bits_data),
    .io_in_rx_dat_bits_dataCheck         (_linkMonitor_1_io_in_rx_dat_bits_dataCheck),
    .io_in_rx_dat_bits_poison            (_linkMonitor_1_io_in_rx_dat_bits_poison),
    .io_in_rx_snp_ready                  (_outer_1_rx_snp_ready_T & ~_rxsnpArb_io_chosen),
    .io_in_rx_snp_valid                  (_linkMonitor_1_io_in_rx_snp_valid),
    .io_in_rx_snp_bits_qos               (_linkMonitor_1_io_in_rx_snp_bits_qos),
    .io_in_rx_snp_bits_srcID             (_linkMonitor_1_io_in_rx_snp_bits_srcID),
    .io_in_rx_snp_bits_txnID             (_linkMonitor_1_io_in_rx_snp_bits_txnID),
    .io_in_rx_snp_bits_fwdNID            (_linkMonitor_1_io_in_rx_snp_bits_fwdNID),
    .io_in_rx_snp_bits_fwdTxnID          (_linkMonitor_1_io_in_rx_snp_bits_fwdTxnID),
    .io_in_rx_snp_bits_opcode            (_linkMonitor_1_io_in_rx_snp_bits_opcode),
    .io_in_rx_snp_bits_addr              (_linkMonitor_1_io_in_rx_snp_bits_addr),
    .io_in_rx_snp_bits_ns                (_linkMonitor_1_io_in_rx_snp_bits_ns),
    .io_in_rx_snp_bits_doNotGoToSD       (_linkMonitor_1_io_in_rx_snp_bits_doNotGoToSD),
    .io_in_rx_snp_bits_retToSrc          (_linkMonitor_1_io_in_rx_snp_bits_retToSrc),
    .io_in_rx_snp_bits_traceTag          (_linkMonitor_1_io_in_rx_snp_bits_traceTag),
    .io_in_rx_snp_bits_mpam_perfMonGroup
      (_linkMonitor_1_io_in_rx_snp_bits_mpam_perfMonGroup),
    .io_in_rx_snp_bits_mpam_partID       (_linkMonitor_1_io_in_rx_snp_bits_mpam_partID),
    .io_in_rx_snp_bits_mpam_mpamNS       (_linkMonitor_1_io_in_rx_snp_bits_mpam_mpamNS),
    .io_out_txsactive                    (_linkMonitor_1_io_out_txsactive),
    .io_out_rxsactive                    (_llcLogger_io_up_rxsactive),
    .io_out_syscoreq                     (_linkMonitor_1_io_out_syscoreq),
    .io_out_syscoack                     (_llcLogger_io_up_syscoack),
    .io_out_tx_linkactivereq             (_linkMonitor_1_io_out_tx_linkactivereq),
    .io_out_tx_linkactiveack             (_llcLogger_io_up_tx_linkactiveack),
    .io_out_tx_req_flitpend              (_linkMonitor_1_io_out_tx_req_flitpend),
    .io_out_tx_req_flitv                 (_linkMonitor_1_io_out_tx_req_flitv),
    .io_out_tx_req_flit                  (_linkMonitor_1_io_out_tx_req_flit),
    .io_out_tx_req_lcrdv                 (_llcLogger_io_up_tx_req_lcrdv),
    .io_out_tx_rsp_flitpend              (_linkMonitor_1_io_out_tx_rsp_flitpend),
    .io_out_tx_rsp_flitv                 (_linkMonitor_1_io_out_tx_rsp_flitv),
    .io_out_tx_rsp_flit                  (_linkMonitor_1_io_out_tx_rsp_flit),
    .io_out_tx_rsp_lcrdv                 (_llcLogger_io_up_tx_rsp_lcrdv),
    .io_out_tx_dat_flitpend              (_linkMonitor_1_io_out_tx_dat_flitpend),
    .io_out_tx_dat_flitv                 (_linkMonitor_1_io_out_tx_dat_flitv),
    .io_out_tx_dat_flit                  (_linkMonitor_1_io_out_tx_dat_flit),
    .io_out_tx_dat_lcrdv                 (_llcLogger_io_up_tx_dat_lcrdv),
    .io_out_rx_linkactivereq             (_llcLogger_io_up_rx_linkactivereq),
    .io_out_rx_linkactiveack             (_linkMonitor_1_io_out_rx_linkactiveack),
    .io_out_rx_rsp_flitpend              (_llcLogger_io_up_rx_rsp_flitpend),
    .io_out_rx_rsp_flitv                 (_llcLogger_io_up_rx_rsp_flitv),
    .io_out_rx_rsp_flit                  (_llcLogger_io_up_rx_rsp_flit),
    .io_out_rx_rsp_lcrdv                 (_linkMonitor_1_io_out_rx_rsp_lcrdv),
    .io_out_rx_dat_flitpend              (_llcLogger_io_up_rx_dat_flitpend),
    .io_out_rx_dat_flitv                 (_llcLogger_io_up_rx_dat_flitv),
    .io_out_rx_dat_flit                  (_llcLogger_io_up_rx_dat_flit),
    .io_out_rx_dat_lcrdv                 (_linkMonitor_1_io_out_rx_dat_lcrdv),
    .io_out_rx_snp_flitpend              (_llcLogger_io_up_rx_snp_flitpend),
    .io_out_rx_snp_flitv                 (_llcLogger_io_up_rx_snp_flitv),
    .io_out_rx_snp_flit                  (_llcLogger_io_up_rx_snp_flit),
    .io_out_rx_snp_lcrdv                 (_linkMonitor_1_io_out_rx_snp_lcrdv)
  );
  TransmitterLinkMonitor linkMonitor_2 (
    .clock                               (io_clock),
    .reset                               (io_reset),
    .io_in_tx_req_ready                  (_linkMonitor_2_io_in_tx_req_ready),
    .io_in_tx_req_valid                  (outer_1_tx_req_valid),
    .io_in_tx_req_bits_qos               (_linkMonitor_io_out_tx_req_bits_qos),
    .io_in_tx_req_bits_tgtID             (linkMonitor_2_io_in_tx_req_bits_tgtID),
    .io_in_tx_req_bits_srcID             (_linkMonitor_io_out_tx_req_bits_srcID),
    .io_in_tx_req_bits_txnID             (_linkMonitor_io_out_tx_req_bits_txnID),
    .io_in_tx_req_bits_returnNID         (_linkMonitor_io_out_tx_req_bits_returnNID),
    .io_in_tx_req_bits_stashNIDValid     (_linkMonitor_io_out_tx_req_bits_stashNIDValid),
    .io_in_tx_req_bits_returnTxnID       (_linkMonitor_io_out_tx_req_bits_returnTxnID),
    .io_in_tx_req_bits_opcode            (_linkMonitor_io_out_tx_req_bits_opcode),
    .io_in_tx_req_bits_size              (_linkMonitor_io_out_tx_req_bits_size),
    .io_in_tx_req_bits_addr              (_linkMonitor_io_out_tx_req_bits_addr),
    .io_in_tx_req_bits_ns                (_linkMonitor_io_out_tx_req_bits_ns),
    .io_in_tx_req_bits_likelyshared      (_linkMonitor_io_out_tx_req_bits_likelyshared),
    .io_in_tx_req_bits_allowRetry        (_linkMonitor_io_out_tx_req_bits_allowRetry),
    .io_in_tx_req_bits_order             (_linkMonitor_io_out_tx_req_bits_order),
    .io_in_tx_req_bits_pCrdType          (_linkMonitor_io_out_tx_req_bits_pCrdType),
    .io_in_tx_req_bits_memAttr_allocate
      (_linkMonitor_io_out_tx_req_bits_memAttr_allocate),
    .io_in_tx_req_bits_memAttr_cacheable
      (_linkMonitor_io_out_tx_req_bits_memAttr_cacheable),
    .io_in_tx_req_bits_memAttr_device    (_linkMonitor_io_out_tx_req_bits_memAttr_device),
    .io_in_tx_req_bits_memAttr_ewa       (_linkMonitor_io_out_tx_req_bits_memAttr_ewa),
    .io_in_tx_req_bits_snpAttr           (_linkMonitor_io_out_tx_req_bits_snpAttr),
    .io_in_tx_req_bits_lpIDWithPadding
      (_linkMonitor_io_out_tx_req_bits_lpIDWithPadding),
    .io_in_tx_req_bits_snoopMe           (_linkMonitor_io_out_tx_req_bits_snoopMe),
    .io_in_tx_req_bits_expCompAck        (_linkMonitor_io_out_tx_req_bits_expCompAck),
    .io_in_tx_req_bits_tagOp             (_linkMonitor_io_out_tx_req_bits_tagOp),
    .io_in_tx_req_bits_traceTag          (_linkMonitor_io_out_tx_req_bits_traceTag),
    .io_in_tx_req_bits_mpam_perfMonGroup
      (_linkMonitor_io_out_tx_req_bits_mpam_perfMonGroup),
    .io_in_tx_req_bits_mpam_partID       (_linkMonitor_io_out_tx_req_bits_mpam_partID),
    .io_in_tx_req_bits_mpam_mpamNS       (_linkMonitor_io_out_tx_req_bits_mpam_mpamNS),
    .io_in_tx_req_bits_rsvdc             (_linkMonitor_io_out_tx_req_bits_rsvdc),
    .io_in_tx_rsp_ready                  (_linkMonitor_2_io_in_tx_rsp_ready),
    .io_in_tx_rsp_valid                  (outer_1_tx_rsp_valid),
    .io_in_tx_rsp_bits_qos               (_linkMonitor_io_out_tx_rsp_bits_qos),
    .io_in_tx_rsp_bits_tgtID             (_linkMonitor_io_out_tx_rsp_bits_tgtID),
    .io_in_tx_rsp_bits_srcID             (_linkMonitor_io_out_tx_rsp_bits_srcID),
    .io_in_tx_rsp_bits_txnID             (_linkMonitor_io_out_tx_rsp_bits_txnID),
    .io_in_tx_rsp_bits_opcode            (_linkMonitor_io_out_tx_rsp_bits_opcode),
    .io_in_tx_rsp_bits_respErr           (_linkMonitor_io_out_tx_rsp_bits_respErr),
    .io_in_tx_rsp_bits_resp              (_linkMonitor_io_out_tx_rsp_bits_resp),
    .io_in_tx_rsp_bits_fwdState          (_linkMonitor_io_out_tx_rsp_bits_fwdState),
    .io_in_tx_rsp_bits_cBusy             (_linkMonitor_io_out_tx_rsp_bits_cBusy),
    .io_in_tx_rsp_bits_dbID              (_linkMonitor_io_out_tx_rsp_bits_dbID),
    .io_in_tx_rsp_bits_pCrdType          (_linkMonitor_io_out_tx_rsp_bits_pCrdType),
    .io_in_tx_rsp_bits_tagOp             (_linkMonitor_io_out_tx_rsp_bits_tagOp),
    .io_in_tx_rsp_bits_traceTag          (_linkMonitor_io_out_tx_rsp_bits_traceTag),
    .io_in_tx_dat_ready                  (_linkMonitor_2_io_in_tx_dat_ready),
    .io_in_tx_dat_valid                  (outer_1_tx_dat_valid),
    .io_in_tx_dat_bits_qos               (_linkMonitor_io_out_tx_dat_bits_qos),
    .io_in_tx_dat_bits_tgtID             (_linkMonitor_io_out_tx_dat_bits_tgtID),
    .io_in_tx_dat_bits_srcID             (_linkMonitor_io_out_tx_dat_bits_srcID),
    .io_in_tx_dat_bits_txnID             (_linkMonitor_io_out_tx_dat_bits_txnID),
    .io_in_tx_dat_bits_homeNID           (_linkMonitor_io_out_tx_dat_bits_homeNID),
    .io_in_tx_dat_bits_opcode            (_linkMonitor_io_out_tx_dat_bits_opcode),
    .io_in_tx_dat_bits_respErr           (_linkMonitor_io_out_tx_dat_bits_respErr),
    .io_in_tx_dat_bits_resp              (_linkMonitor_io_out_tx_dat_bits_resp),
    .io_in_tx_dat_bits_dataSource        (_linkMonitor_io_out_tx_dat_bits_dataSource),
    .io_in_tx_dat_bits_cBusy             (_linkMonitor_io_out_tx_dat_bits_cBusy),
    .io_in_tx_dat_bits_dbID              (_linkMonitor_io_out_tx_dat_bits_dbID),
    .io_in_tx_dat_bits_ccID              (_linkMonitor_io_out_tx_dat_bits_ccID),
    .io_in_tx_dat_bits_dataID            (_linkMonitor_io_out_tx_dat_bits_dataID),
    .io_in_tx_dat_bits_tagOp             (_linkMonitor_io_out_tx_dat_bits_tagOp),
    .io_in_tx_dat_bits_tag               (_linkMonitor_io_out_tx_dat_bits_tag),
    .io_in_tx_dat_bits_tu                (_linkMonitor_io_out_tx_dat_bits_tu),
    .io_in_tx_dat_bits_traceTag          (_linkMonitor_io_out_tx_dat_bits_traceTag),
    .io_in_tx_dat_bits_rsvdc             (_linkMonitor_io_out_tx_dat_bits_rsvdc),
    .io_in_tx_dat_bits_be                (_linkMonitor_io_out_tx_dat_bits_be),
    .io_in_tx_dat_bits_data              (_linkMonitor_io_out_tx_dat_bits_data),
    .io_in_tx_dat_bits_dataCheck         (_linkMonitor_io_out_tx_dat_bits_dataCheck),
    .io_in_tx_dat_bits_poison            (_linkMonitor_io_out_tx_dat_bits_poison),
    .io_in_rx_rsp_ready                  (_outer_1_rx_rsp_ready_T & _rxrspArb_io_chosen),
    .io_in_rx_rsp_valid                  (_linkMonitor_2_io_in_rx_rsp_valid),
    .io_in_rx_rsp_bits_qos               (_linkMonitor_2_io_in_rx_rsp_bits_qos),
    .io_in_rx_rsp_bits_tgtID             (_linkMonitor_2_io_in_rx_rsp_bits_tgtID),
    .io_in_rx_rsp_bits_srcID             (_linkMonitor_2_io_in_rx_rsp_bits_srcID),
    .io_in_rx_rsp_bits_txnID             (_linkMonitor_2_io_in_rx_rsp_bits_txnID),
    .io_in_rx_rsp_bits_opcode            (_linkMonitor_2_io_in_rx_rsp_bits_opcode),
    .io_in_rx_rsp_bits_respErr           (_linkMonitor_2_io_in_rx_rsp_bits_respErr),
    .io_in_rx_rsp_bits_resp              (_linkMonitor_2_io_in_rx_rsp_bits_resp),
    .io_in_rx_rsp_bits_fwdState          (_linkMonitor_2_io_in_rx_rsp_bits_fwdState),
    .io_in_rx_rsp_bits_cBusy             (_linkMonitor_2_io_in_rx_rsp_bits_cBusy),
    .io_in_rx_rsp_bits_dbID              (_linkMonitor_2_io_in_rx_rsp_bits_dbID),
    .io_in_rx_rsp_bits_pCrdType          (_linkMonitor_2_io_in_rx_rsp_bits_pCrdType),
    .io_in_rx_rsp_bits_tagOp             (_linkMonitor_2_io_in_rx_rsp_bits_tagOp),
    .io_in_rx_rsp_bits_traceTag          (_linkMonitor_2_io_in_rx_rsp_bits_traceTag),
    .io_in_rx_dat_ready                  (_outer_1_rx_dat_ready_T & _rxdatArb_io_chosen),
    .io_in_rx_dat_valid                  (_linkMonitor_2_io_in_rx_dat_valid),
    .io_in_rx_dat_bits_qos               (_linkMonitor_2_io_in_rx_dat_bits_qos),
    .io_in_rx_dat_bits_tgtID             (_linkMonitor_2_io_in_rx_dat_bits_tgtID),
    .io_in_rx_dat_bits_srcID             (_linkMonitor_2_io_in_rx_dat_bits_srcID),
    .io_in_rx_dat_bits_txnID             (_linkMonitor_2_io_in_rx_dat_bits_txnID),
    .io_in_rx_dat_bits_homeNID           (_linkMonitor_2_io_in_rx_dat_bits_homeNID),
    .io_in_rx_dat_bits_opcode            (_linkMonitor_2_io_in_rx_dat_bits_opcode),
    .io_in_rx_dat_bits_respErr           (_linkMonitor_2_io_in_rx_dat_bits_respErr),
    .io_in_rx_dat_bits_resp              (_linkMonitor_2_io_in_rx_dat_bits_resp),
    .io_in_rx_dat_bits_dataSource        (_linkMonitor_2_io_in_rx_dat_bits_dataSource),
    .io_in_rx_dat_bits_cBusy             (_linkMonitor_2_io_in_rx_dat_bits_cBusy),
    .io_in_rx_dat_bits_dbID              (_linkMonitor_2_io_in_rx_dat_bits_dbID),
    .io_in_rx_dat_bits_ccID              (_linkMonitor_2_io_in_rx_dat_bits_ccID),
    .io_in_rx_dat_bits_dataID            (_linkMonitor_2_io_in_rx_dat_bits_dataID),
    .io_in_rx_dat_bits_tagOp             (_linkMonitor_2_io_in_rx_dat_bits_tagOp),
    .io_in_rx_dat_bits_tag               (_linkMonitor_2_io_in_rx_dat_bits_tag),
    .io_in_rx_dat_bits_tu                (_linkMonitor_2_io_in_rx_dat_bits_tu),
    .io_in_rx_dat_bits_traceTag          (_linkMonitor_2_io_in_rx_dat_bits_traceTag),
    .io_in_rx_dat_bits_rsvdc             (_linkMonitor_2_io_in_rx_dat_bits_rsvdc),
    .io_in_rx_dat_bits_be                (_linkMonitor_2_io_in_rx_dat_bits_be),
    .io_in_rx_dat_bits_data              (_linkMonitor_2_io_in_rx_dat_bits_data),
    .io_in_rx_dat_bits_dataCheck         (_linkMonitor_2_io_in_rx_dat_bits_dataCheck),
    .io_in_rx_dat_bits_poison            (_linkMonitor_2_io_in_rx_dat_bits_poison),
    .io_in_rx_snp_ready                  (_outer_1_rx_snp_ready_T & _rxsnpArb_io_chosen),
    .io_in_rx_snp_valid                  (_linkMonitor_2_io_in_rx_snp_valid),
    .io_in_rx_snp_bits_qos               (_linkMonitor_2_io_in_rx_snp_bits_qos),
    .io_in_rx_snp_bits_srcID             (_linkMonitor_2_io_in_rx_snp_bits_srcID),
    .io_in_rx_snp_bits_txnID             (_linkMonitor_2_io_in_rx_snp_bits_txnID),
    .io_in_rx_snp_bits_fwdNID            (_linkMonitor_2_io_in_rx_snp_bits_fwdNID),
    .io_in_rx_snp_bits_fwdTxnID          (_linkMonitor_2_io_in_rx_snp_bits_fwdTxnID),
    .io_in_rx_snp_bits_opcode            (_linkMonitor_2_io_in_rx_snp_bits_opcode),
    .io_in_rx_snp_bits_addr              (_linkMonitor_2_io_in_rx_snp_bits_addr),
    .io_in_rx_snp_bits_ns                (_linkMonitor_2_io_in_rx_snp_bits_ns),
    .io_in_rx_snp_bits_doNotGoToSD       (_linkMonitor_2_io_in_rx_snp_bits_doNotGoToSD),
    .io_in_rx_snp_bits_retToSrc          (_linkMonitor_2_io_in_rx_snp_bits_retToSrc),
    .io_in_rx_snp_bits_traceTag          (_linkMonitor_2_io_in_rx_snp_bits_traceTag),
    .io_in_rx_snp_bits_mpam_perfMonGroup
      (_linkMonitor_2_io_in_rx_snp_bits_mpam_perfMonGroup),
    .io_in_rx_snp_bits_mpam_partID       (_linkMonitor_2_io_in_rx_snp_bits_mpam_partID),
    .io_in_rx_snp_bits_mpam_mpamNS       (_linkMonitor_2_io_in_rx_snp_bits_mpam_mpamNS),
    .io_out_txsactive                    (_linkMonitor_2_io_out_txsactive),
    .io_out_rxsactive                    (_mmioLogger_io_up_rxsactive),
    .io_out_syscoreq                     (_linkMonitor_2_io_out_syscoreq),
    .io_out_syscoack                     (_mmioLogger_io_up_syscoack),
    .io_out_tx_linkactivereq             (_linkMonitor_2_io_out_tx_linkactivereq),
    .io_out_tx_linkactiveack             (_mmioLogger_io_up_tx_linkactiveack),
    .io_out_tx_req_flitpend              (_linkMonitor_2_io_out_tx_req_flitpend),
    .io_out_tx_req_flitv                 (_linkMonitor_2_io_out_tx_req_flitv),
    .io_out_tx_req_flit                  (_linkMonitor_2_io_out_tx_req_flit),
    .io_out_tx_req_lcrdv                 (_mmioLogger_io_up_tx_req_lcrdv),
    .io_out_tx_rsp_flitpend              (_linkMonitor_2_io_out_tx_rsp_flitpend),
    .io_out_tx_rsp_flitv                 (_linkMonitor_2_io_out_tx_rsp_flitv),
    .io_out_tx_rsp_flit                  (_linkMonitor_2_io_out_tx_rsp_flit),
    .io_out_tx_rsp_lcrdv                 (_mmioLogger_io_up_tx_rsp_lcrdv),
    .io_out_tx_dat_flitpend              (_linkMonitor_2_io_out_tx_dat_flitpend),
    .io_out_tx_dat_flitv                 (_linkMonitor_2_io_out_tx_dat_flitv),
    .io_out_tx_dat_flit                  (_linkMonitor_2_io_out_tx_dat_flit),
    .io_out_tx_dat_lcrdv                 (_mmioLogger_io_up_tx_dat_lcrdv),
    .io_out_rx_linkactivereq             (_mmioLogger_io_up_rx_linkactivereq),
    .io_out_rx_linkactiveack             (_linkMonitor_2_io_out_rx_linkactiveack),
    .io_out_rx_rsp_flitpend              (_mmioLogger_io_up_rx_rsp_flitpend),
    .io_out_rx_rsp_flitv                 (_mmioLogger_io_up_rx_rsp_flitv),
    .io_out_rx_rsp_flit                  (_mmioLogger_io_up_rx_rsp_flit),
    .io_out_rx_rsp_lcrdv                 (_linkMonitor_2_io_out_rx_rsp_lcrdv),
    .io_out_rx_dat_flitpend              (_mmioLogger_io_up_rx_dat_flitpend),
    .io_out_rx_dat_flitv                 (_mmioLogger_io_up_rx_dat_flitv),
    .io_out_rx_dat_flit                  (_mmioLogger_io_up_rx_dat_flit),
    .io_out_rx_dat_lcrdv                 (_linkMonitor_2_io_out_rx_dat_lcrdv),
    .io_out_rx_snp_flitpend              (_mmioLogger_io_up_rx_snp_flitpend),
    .io_out_rx_snp_flitv                 (_mmioLogger_io_up_rx_snp_flitv),
    .io_out_rx_snp_flit                  (_mmioLogger_io_up_rx_snp_flit),
    .io_out_rx_snp_lcrdv                 (_linkMonitor_2_io_out_rx_snp_lcrdv)
  );
  CHILogger memLogger (
    .io_up_txsactive          (_chi_openllc_opt_io_sn_txsactive),
    .io_up_rxsactive          (_memLogger_io_up_rxsactive),
    .io_up_syscoreq           (1'h0),
    .io_up_syscoack           (/* unused */),
    .io_up_tx_linkactivereq   (_chi_openllc_opt_io_sn_tx_linkactivereq),
    .io_up_tx_linkactiveack   (_memLogger_io_up_tx_linkactiveack),
    .io_up_tx_req_flitpend    (_chi_openllc_opt_io_sn_tx_req_flitpend),
    .io_up_tx_req_flitv       (_chi_openllc_opt_io_sn_tx_req_flitv),
    .io_up_tx_req_flit        (_chi_openllc_opt_io_sn_tx_req_flit),
    .io_up_tx_req_lcrdv       (_memLogger_io_up_tx_req_lcrdv),
    .io_up_tx_rsp_flitpend    (1'h0),
    .io_up_tx_rsp_flitv       (1'h0),
    .io_up_tx_rsp_flit        (73'h0),
    .io_up_tx_rsp_lcrdv       (/* unused */),
    .io_up_tx_dat_flitpend    (_chi_openllc_opt_io_sn_tx_dat_flitpend),
    .io_up_tx_dat_flitv       (_chi_openllc_opt_io_sn_tx_dat_flitv),
    .io_up_tx_dat_flit        (_chi_openllc_opt_io_sn_tx_dat_flit),
    .io_up_tx_dat_lcrdv       (_memLogger_io_up_tx_dat_lcrdv),
    .io_up_rx_linkactivereq   (_memLogger_io_up_rx_linkactivereq),
    .io_up_rx_linkactiveack   (_chi_openllc_opt_io_sn_rx_linkactiveack),
    .io_up_rx_rsp_flitpend    (_memLogger_io_up_rx_rsp_flitpend),
    .io_up_rx_rsp_flitv       (_memLogger_io_up_rx_rsp_flitv),
    .io_up_rx_rsp_flit        (_memLogger_io_up_rx_rsp_flit),
    .io_up_rx_rsp_lcrdv       (_chi_openllc_opt_io_sn_rx_rsp_lcrdv),
    .io_up_rx_dat_flitpend    (_memLogger_io_up_rx_dat_flitpend),
    .io_up_rx_dat_flitv       (_memLogger_io_up_rx_dat_flitv),
    .io_up_rx_dat_flit        (_memLogger_io_up_rx_dat_flit),
    .io_up_rx_dat_lcrdv       (_chi_openllc_opt_io_sn_rx_dat_lcrdv),
    .io_up_rx_snp_flitpend    (/* unused */),
    .io_up_rx_snp_flitv       (/* unused */),
    .io_up_rx_snp_flit        (/* unused */),
    .io_up_rx_snp_lcrdv       (1'h0),
    .io_down_txsactive        (_memLogger_io_down_txsactive),
    .io_down_rxsactive        (_chi_llcBridge_opt_io_chi_rxsactive),
    .io_down_syscoreq         (/* unused */),
    .io_down_syscoack         (1'h0),
    .io_down_tx_linkactivereq (_memLogger_io_down_tx_linkactivereq),
    .io_down_tx_linkactiveack (_chi_llcBridge_opt_io_chi_tx_linkactiveack),
    .io_down_tx_req_flitpend  (_memLogger_io_down_tx_req_flitpend),
    .io_down_tx_req_flitv     (_memLogger_io_down_tx_req_flitv),
    .io_down_tx_req_flit      (_memLogger_io_down_tx_req_flit),
    .io_down_tx_req_lcrdv     (_chi_llcBridge_opt_io_chi_tx_req_lcrdv),
    .io_down_tx_rsp_flitpend  (/* unused */),
    .io_down_tx_rsp_flitv     (/* unused */),
    .io_down_tx_rsp_flit      (/* unused */),
    .io_down_tx_rsp_lcrdv     (1'h0),
    .io_down_tx_dat_flitpend  (_memLogger_io_down_tx_dat_flitpend),
    .io_down_tx_dat_flitv     (_memLogger_io_down_tx_dat_flitv),
    .io_down_tx_dat_flit      (_memLogger_io_down_tx_dat_flit),
    .io_down_tx_dat_lcrdv     (_chi_llcBridge_opt_io_chi_tx_dat_lcrdv),
    .io_down_rx_linkactivereq (_chi_llcBridge_opt_io_chi_rx_linkactivereq),
    .io_down_rx_linkactiveack (_memLogger_io_down_rx_linkactiveack),
    .io_down_rx_rsp_flitpend  (_chi_llcBridge_opt_io_chi_rx_rsp_flitpend),
    .io_down_rx_rsp_flitv     (_chi_llcBridge_opt_io_chi_rx_rsp_flitv),
    .io_down_rx_rsp_flit      (_chi_llcBridge_opt_io_chi_rx_rsp_flit),
    .io_down_rx_rsp_lcrdv     (_memLogger_io_down_rx_rsp_lcrdv),
    .io_down_rx_dat_flitpend  (_chi_llcBridge_opt_io_chi_rx_dat_flitpend),
    .io_down_rx_dat_flitv     (_chi_llcBridge_opt_io_chi_rx_dat_flitv),
    .io_down_rx_dat_flit      (_chi_llcBridge_opt_io_chi_rx_dat_flit),
    .io_down_rx_dat_lcrdv     (_memLogger_io_down_rx_dat_lcrdv),
    .io_down_rx_snp_flitpend  (1'h0),
    .io_down_rx_snp_flitv     (1'h0),
    .io_down_rx_snp_flit      (115'h0),
    .io_down_rx_snp_lcrdv     (/* unused */)
  );
  ResetGen resetGen (
    .clock         (io_clock),
    .reset         (_reset_sync_resetSync_o_reset),
    .o_reset       (_resetGen_o_reset),
    .dft_lgc_rst_n (1'h0),
    .dft_mode      (1'h0),
    .dft_scan_mode (1'h0)
  );
  ResetGen resetGen_1 (
    .clock         (io_clock),
    .reset
      (_resetGen_o_reset | _nocMisc_debug_module_io_resetCtrl_hartResetReq_0),
    .o_reset       (_resetGen_1_o_reset),
    .dft_lgc_rst_n (1'h0),
    .dft_mode      (1'h0),
    .dft_scan_mode (1'h0)
  );
  assign io_traceCoreInterface_0_toEncoder_valid =
    {_core_with_l2_io_traceCoreInterface_toEncoder_groups_2_valid,
     _core_with_l2_io_traceCoreInterface_toEncoder_groups_1_valid,
     _core_with_l2_io_traceCoreInterface_toEncoder_groups_0_valid};
  assign io_traceCoreInterface_0_toEncoder_iaddr =
    {_core_with_l2_io_traceCoreInterface_toEncoder_groups_2_bits_iaddr,
     _core_with_l2_io_traceCoreInterface_toEncoder_groups_1_bits_iaddr,
     _core_with_l2_io_traceCoreInterface_toEncoder_groups_0_bits_iaddr};
  assign io_traceCoreInterface_0_toEncoder_itype =
    {_core_with_l2_io_traceCoreInterface_toEncoder_groups_2_bits_itype,
     _core_with_l2_io_traceCoreInterface_toEncoder_groups_1_bits_itype,
     _core_with_l2_io_traceCoreInterface_toEncoder_groups_0_bits_itype};
  assign io_traceCoreInterface_0_toEncoder_iretire =
    {_core_with_l2_io_traceCoreInterface_toEncoder_groups_2_bits_iretire,
     _core_with_l2_io_traceCoreInterface_toEncoder_groups_1_bits_iretire,
     _core_with_l2_io_traceCoreInterface_toEncoder_groups_0_bits_iretire};
  assign io_traceCoreInterface_0_toEncoder_ilastsize =
    {_core_with_l2_io_traceCoreInterface_toEncoder_groups_2_bits_ilastsize,
     _core_with_l2_io_traceCoreInterface_toEncoder_groups_1_bits_ilastsize,
     _core_with_l2_io_traceCoreInterface_toEncoder_groups_0_bits_ilastsize};
endmodule

