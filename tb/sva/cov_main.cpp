// Verilator main that writes coverage.dat at the end (the --binary main of Verilator 5.020 does not).
#include "Vtb_core_regression.h"
#include "verilated.h"
#include "verilated_cov.h"
#include <memory>
int main(int argc, char** argv) {
  const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
  contextp->commandArgs(argc, argv);
  const std::unique_ptr<Vtb_core_regression> topp{new Vtb_core_regression{contextp.get(), ""}};
  while (!contextp->gotFinish()) {
    topp->eval();
    if (!topp->eventsPending()) break;
    contextp->time(topp->nextTimeSlot());
  }
  topp->final();
  contextp->coveragep()->write("coverage.dat");
  return 0;
}
