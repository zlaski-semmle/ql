private import cpp
private import DataFlowUtil
private import DataFlowDispatch

/** Gets the instance argument of a non-static call. */
private Node getInstanceArgument(Call call) {
  result.asExpr() = call.getQualifier()
  or
  // For constructors, there is no qualifier, so we pretend the call itself
  // is the instance argument.
  result.asExpr() = call.(ConstructorCall)
  // This does not include the implicit `this` argument on auto-generated
  // base class destructor calls as those do not have an AST element.
}

/** An argument to a call. */
private class Argument extends Expr {
  Call call;

  int pos;

  Argument() { call.getArgument(pos) = this }

  /** Gets the call that has this argument. */
  Call getCall() { result = call }

  /** Gets the position of this argument. */
  int getPosition() { result = pos }
}

/**
 * A data flow node that occurs as the argument of a call and is passed as-is
 * to the callable. Arguments that are wrapped in an implicit varargs array
 * creation are not included, but the implicitly created array is.
 * Instance arguments are also included.
 */
class ArgumentNode extends Node {
  ArgumentNode() {
    exists(Argument arg | this.asExpr() = arg) or
    this = getInstanceArgument(_)
  }

  /**
   * Holds if this argument occurs at the given position in the given call.
   * The instance argument is considered to have index `-1`.
   */
  predicate argumentOf(DataFlowCall call, int pos) {
    exists(Argument arg | this.asExpr() = arg | call = arg.getCall() and pos = arg.getPosition())
    or
    pos = -1 and this = getInstanceArgument(call)
  }

  /** Gets the call in which this node is an argument. */
  DataFlowCall getCall() { this.argumentOf(result, _) }
}

private newtype TReturnKind = TNormalReturnKind()

/**
 * A return kind. A return kind describes how a value can be returned
 * from a callable. For C++, this is simply a function return.
 */
class ReturnKind extends TReturnKind {
  /** Gets a textual representation of this return kind. */
  string toString() { result = "return" }
}

/** A data flow node that occurs as the result of a `ReturnStmt`. */
class ReturnNode extends ExprNode {
  ReturnNode() { exists(ReturnStmt ret | this.getExpr() = ret.getExpr()) }

  /** Gets the kind of this returned value. */
  ReturnKind getKind() { result = TNormalReturnKind() }
}

/** A data flow node that represents the output of a call. */
class OutNode extends ExprNode {
  OutNode() { this.getExpr() instanceof Call }

  /** Gets the underlying call. */
  DataFlowCall getCall() { result = this.getExpr() }
}

/**
 * Gets a node that can read the value returned from `call` with return kind
 * `kind`.
 */
OutNode getAnOutNode(DataFlowCall call, ReturnKind kind) {
  result = call.getNode() and
  kind = TNormalReturnKind()
}

/**
 * Holds if data can flow from `node1` to `node2` in a way that loses the
 * calling context. For example, this would happen with flow through a
 * global or static variable.
 */
predicate jumpStep(Node n1, Node n2) { none() }

/**
 * Holds if `call` passes an implicit or explicit qualifier, i.e., a
 * `this` parameter.
 */
predicate callHasQualifier(Call call) {
  call.hasQualifier()
  or
  call.getTarget() instanceof Destructor
}

private newtype TContent =
  TFieldContent(Field f) or
  TCollectionContent() or
  TArrayContent()

/**
 * A reference contained in an object. Examples include instance fields, the
 * contents of a collection object, or the contents of an array.
 */
class Content extends TContent {
  /** Gets a textual representation of this element. */
  abstract string toString();

  predicate hasLocationInfo(string path, int sl, int sc, int el, int ec) {
    path = "" and sl = 0 and sc = 0 and el = 0 and ec = 0
  }

  /** Gets the type of the object containing this content. */
  abstract Type getContainerType();

  /** Gets the type of this content. */
  abstract Type getType();
}

private class FieldContent extends Content, TFieldContent {
  Field f;

  FieldContent() { this = TFieldContent(f) }

  Field getField() { result = f }

  override string toString() { result = f.toString() }

  override predicate hasLocationInfo(string path, int sl, int sc, int el, int ec) {
    f.getLocation().hasLocationInfo(path, sl, sc, el, ec)
  }

  override Type getContainerType() { result = f.getDeclaringType() }

  override Type getType() { result = f.getType() }
}

private class CollectionContent extends Content, TCollectionContent {
  override string toString() { result = "collection" }

  override Type getContainerType() { none() }

  override Type getType() { none() }
}

private class ArrayContent extends Content, TArrayContent {
  override string toString() { result = "array" }

  override Type getContainerType() { none() }

  override Type getType() { none() }
}

/**
 * Holds if data can flow from `node1` to `node2` via an assignment to `f`.
 * Thus, `node2` references an object with a field `f` that contains the
 * value of `node1`.
 */
predicate storeStep(Node node1, Content f, PostUpdateNode node2) {
  exists(FieldAccess fa |
    exists(Assignment a |
      (a.getRValue() = node1.asExpr() or node1.asExpr() = a) and
      a.getLValue() = fa
    ) and
    not fa.getTarget().isStatic() and
    node2.getPreUpdateNode().asExpr() = fa.getQualifier() and
    f.(FieldContent).getField() = fa.getTarget()
  )
}

/**
 * Holds if data can flow from `node1` to `node2` via a read of `f`.
 * Thus, `node1` references an object with a field `f` whose value ends up in
 * `node2`.
 */
predicate readStep(Node node1, Content f, Node node2) {
  exists(FieldAccess fr |
    node1.asExpr() = fr.getQualifier() and
    fr.getTarget() = f.(FieldContent).getField() and
    fr = node2.asExpr() and
    not fr = any(AssignExpr a).getLValue()
  )
}

/**
 * Gets a representative (boxed) type for `t` for the purpose of pruning
 * possible flow. A single type is used for all numeric types to account for
 * numeric conversions, and otherwise the erasure is used.
 */
Type getErasedRepr(Type t) {
  suppressUnusedType(t) and
  result instanceof VoidType // stub implementation
}

/** Gets a string representation of a type returned by `getErasedRepr`. */
string ppReprType(Type t) { result = t.toString() }

/**
 * Holds if `t1` and `t2` are compatible, that is, whether data can flow from
 * a node of type `t1` to a node of type `t2`.
 */
pragma[inline]
predicate compatibleTypes(Type t1, Type t2) {
  any() // stub implementation
}

private predicate suppressUnusedType(Type t) { any() }

//////////////////////////////////////////////////////////////////////////////
// Java QL library compatibility wrappers
//////////////////////////////////////////////////////////////////////////////
/** A node that performs a type cast. */
class CastNode extends Node {
  CastNode() { none() } // stub implementation
}

class DataFlowCallable = Function;

class DataFlowExpr = Expr;

class DataFlowType = Type;

class DataFlowLocation = Location;

/** A function call relevant for data flow. */
class DataFlowCall extends Expr {
  DataFlowCall() { this instanceof Call }

  /**
   * Gets the nth argument for this call.
   *
   * The range of `n` is from `0` to `getNumberOfArguments() - 1`.
   */
  Expr getArgument(int n) { result = this.(Call).getArgument(n) }

  /** Gets the data flow node corresponding to this call. */
  ExprNode getNode() { result.getExpr() = this }

  /** Gets the enclosing callable of this call. */
  Function getEnclosingCallable() { result = this.getEnclosingFunction() }
}
