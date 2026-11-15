Adaptive-threshold engine of the selected research paper (L1: Guo & Wu, Applied Sciences 13(2):870, 2023):
frame buffer, 256-bin histogram, log-domain division-free Otsu, T_lo = T_hi/2, classifier.

Origin: the "reference RTL" zip used by the group (supplied RTL; not written in this repository). The only change made to it
is the rename `bins` -> `hist_bins` in paper_histogram/paper_top (`bins` is a reserved word in Icarus). Everything else is as supplied.
It is a study/comparison artifact: it is NOT part of the shipped FPGA design (the whole-frame buffer does not fit the Z7-10/Zybo).
