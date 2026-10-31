# Transformer FPGA Accelerator Thesis

研究生毕业设计：面向 Transformer 编码器的 FPGA 硬件加速，探索 PTQ/量化、脉动阵列、非线性算子近似，以及 TTA 风格的指令调度与受限编译流程。

## 规划基线

请先阅读 [Thesis plan](THESIS_PLAN.md)。模型、目标 FPGA 和最终量化格式仍需在前期阶段确认。

## 目录

- `脉动阵列设计/rtl/`：已有 RTL 设计与后续硬件实现的主要参考目录。
- `THESIS_PLAN.md`：整体技术路线、阶段任务和评估指标（跨平台 ASCII 文件名，便于其他任务窗口读取）。

Vivado 仿真/综合生成物、数据集与测试二进制、论文 PDF、视频和演示文稿不纳入版本库。旧的 `脉动阵列设计/2ndNationTPU/` 归档工程与当前 RTL 有重复，暂不纳入；需要共享的可复现测试输入应以小型文本样例或生成脚本维护。

## 版本记录

代码和文档按阶段提交，提交说明尽量包含模块/阶段和变化目的，例如 `rtl: add fixed-point GELU PWL unit`。
