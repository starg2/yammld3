
module yammld3.eval;

import std.conv : to;

import yammld3.ast;
import yammld3.common;
import yammld3.diagnostics : DiagnosticsHandler;

package alias TimeEvaluator = float delegate(float startTime, TimeLiteral t);
package alias ExpressionMacroExpander = Expression delegate(ExpressionMacroInvocationExpression emi);

package final class DurationExpressionEvaluator
{
    public this(DiagnosticsHandler handler, TimeEvaluator timeEval, ExpressionMacroExpander macroExpander)
    {
        _diagnosticsHandler = handler;
        _timeEval = timeEval;
        _macroExpander = macroExpander;
    }

    public float evaluate(float startTick, Expression expr)
    {
        if (expr is null)
        {
            return 0.0f;
        }

        return expr.visit!(
            (IntegerLiteral il) => il.value > 0 ? 4.0f / il.value.to!float : 0.0f,
            (DurationLiteral dl)
            {
                import std.math : pow;
                float n = dl.denominator > 0 ? 4.0f / dl.denominator.to!float : 0.0f;
                return n * (2.0f - pow(0.5f, dl.dot.to!float));
            },
            (TimeLiteral tl) => _timeEval(startTick, tl),
            (ExpressionMacroInvocationExpression emi) => evaluate(startTick, _macroExpander(emi)),
            (UnaryExpression ue)
            {
                switch (ue.op.kind)
                {
                case OperatorKind.plus:
                    return +evaluate(startTick, ue.operand);

                case OperatorKind.minus:
                    return -evaluate(startTick, ue.operand);

                case OperatorKind.logicalNot:
                    _diagnosticsHandler.unexpectedExpressionKind(expr.location, "duration");
                    return 0.0f;

                default:
                    assert(false);
                }
            },
            (BinaryExpression be)
            {
                if (be.op.kind == OperatorKind.plus)
                {
                    return evaluate(startTick, be.left) + evaluate(startTick, be.right);
                }
                else if (be.op.kind == OperatorKind.minus)
                {
                    return evaluate(startTick, be.left) - evaluate(startTick, be.right);
                }
                else
                {
                    _diagnosticsHandler.unexpectedExpressionKind(expr.location, "duration");
                    return 0.0f;
                }
            },
            (x)
            {
                _diagnosticsHandler.unexpectedExpressionKind(expr.location, "duration");
                return 0.0f;
            }
        );
    }

    private DiagnosticsHandler _diagnosticsHandler;
    private TimeEvaluator _timeEval;
    private ExpressionMacroExpander _macroExpander;
}

package final class NumericExpressionEvaluator(T)
{
    public this(DiagnosticsHandler handler, ExpressionMacroExpander macroExpander)
    {
        _diagnosticsHandler = handler;
        _macroExpander = macroExpander;
    }

    public T evaluate(Expression expr)
    {
        if (expr is null)
        {
            return 0;
        }

        return expr.visit!(
            (IntegerLiteral il) => il.value,
            (ExpressionMacroInvocationExpression emi) => evaluate(_macroExpander(emi)),
            (UnaryExpression ue)
            {
                switch (ue.op.kind)
                {
                case OperatorKind.plus:
                    return +evaluate(ue.operand);

                case OperatorKind.minus:
                    return -evaluate(ue.operand);

                case OperatorKind.logicalNot:
                    return !evaluate(ue.operand);

                default:
                    assert(false);
                }
            },
            (BinaryExpression be)
            {
                final switch (be.op.kind)
                {
                case OperatorKind.plus:
                    return evaluate(be.left) + evaluate(be.right);

                case OperatorKind.minus:
                    return evaluate(be.left) - evaluate(be.right);

                case OperatorKind.star:
                    return evaluate(be.left) * evaluate(be.right);

                case OperatorKind.slash:
                    {
                        T l = evaluate(be.left);
                        T r = evaluate(be.right);

                        if (r == 0)
                        {
                            _diagnosticsHandler.divideBy0(be.location);
                            return l;
                        }
                        else
                        {
                            return l / r;
                        }
                    }

                case OperatorKind.logicalNot:
                    assert(false);

                case OperatorKind.lessThan:
                    return evaluate(be.left) < evaluate(be.right);

                case OperatorKind.greaterThan:
                    return evaluate(be.left) > evaluate(be.right);

                case OperatorKind.lessThanOrEqual:
                    return evaluate(be.left) <= evaluate(be.right);

                case OperatorKind.greaterThanOrEqual:
                    return evaluate(be.left) >= evaluate(be.right);

                case OperatorKind.equal:
                    return evaluate(be.left) == evaluate(be.right);

                case OperatorKind.notEqual:
                    return evaluate(be.left) != evaluate(be.right);

                case OperatorKind.logicalAnd:
                    return evaluate(be.left) && evaluate(be.right);

                case OperatorKind.logicalOr:
                    return evaluate(be.left) || evaluate(be.right);
                }
            },
            (x)
            {
                _diagnosticsHandler.unexpectedExpressionKind(expr.location, "numeric expression");
                return 0;
            }
        );
    }

    private DiagnosticsHandler _diagnosticsHandler;
    private ExpressionMacroExpander _macroExpander;
}

package final class StringExpressionEvaluator
{
    import std.array : Appender, appender;

    public this(DiagnosticsHandler handler, ExpressionMacroExpander macroExpander)
    {
        _diagnosticsHandler = handler;
        _macroExpander = macroExpander;
    }

    public string evaluate(Expression expr)
    {
        if (expr is null)
        {
            return "";
        }

        auto str = appender!string();
        evaluate(str, expr);
        return str[];
    }

    public void evaluate(Appender!string str, Expression expr)
    {
        if (expr is null)
        {
            return;
        }

        expr.visit!(
            (StringLiteral sl)
            {
                str ~= sl.value;
            },
            (ExpressionMacroInvocationExpression emi)
            {
                evaluate(str, _macroExpander(emi));
            },
            (BinaryExpression be)
            {
                if (be.op.kind == OperatorKind.plus)
                {
                    evaluate(str, be.left);
                    evaluate(str, be.right);
                }
                else
                {
                    _diagnosticsHandler.unexpectedExpressionKind(expr.location, "string");
                }
            },
            (x)
            {
                _diagnosticsHandler.unexpectedExpressionKind(expr.location, "string");
            }
        );
    }

    private DiagnosticsHandler _diagnosticsHandler;
    private ExpressionMacroExpander _macroExpander;
}
