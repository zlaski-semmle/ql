/**
 * @name Call to `memset` may be deleted
 * @description Calling `memset` or `bzero` on a buffer in order to clear its contents may get optimized away
 *              by the compiler if the buffer is not subsequently used.  This is not desirable
 *              behavior if the buffer contains sensitive data that could be exploited by an attacker.
 * @kind problem
 * @problem.severity recommendation
 * @precision high
 * @id cpp/memset-may-be-deleted
 * @tags security
 *       external/cwe/cwe-14
 */

import cpp
import semmle.code.cpp.ir.IR
import semmle.code.cpp.ir.ValueNumbering
import semmle.code.cpp.models.implementations.Memset

class MemsetCallInstruction extends CallInstruction {
  MemsetCallInstruction() { this.getStaticCallTarget() instanceof MemsetFunction }
}

Instruction getAUseInstruction(Instruction insn) { result = insn.getAUse().getUse() }

predicate pointsIntoStack(Instruction instr) {
  instr.(VariableAddressInstruction).getIRVariable() instanceof IRAutomaticVariable
  or
  pointsIntoStack(instr.(CopyInstruction).getSourceValue())
  or
  pointsIntoStack(instr.(ConvertInstruction).getUnary())
}

from MemsetCallInstruction memset, SizedBufferMustWriteSideEffectInstruction sei
where
  sei.getPrimaryInstruction() = memset and
  // The first argument to memset must reside on the stack
  pointsIntoStack(valueNumber(memset.getPositionalArgument(0)).getAnInstruction()) and
  // The result of memset may not be subsequently used
  forall(Instruction use | use = getAUseInstruction+(sei) | use instanceof ChiInstruction)
select memset,
  "Call to " + memset.getStaticCallTarget().getName() + " may be deleted by the compiler."
