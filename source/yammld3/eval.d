
module yammld3.eval;

import std.conv : to;

import yammld3.ast;
import yammld3.common;
import yammld3.diagnostics : DiagnosticsHandler;

package alias TimeEvaluator = float delegate(float startTime, TimeLiteral t);

package final class DurationExpressionEvaluator
{
    public this(DiagnosticsHandler handler, TimeEvaluator timeEval)
    {
        _diagnosticsHandler = handler;
        _timeEval = timeEval;
    }

    public float evaluate(float startTick, Expression expr)
    {
        assert(expr !is null);
        return expr.visit!(
            (IntegerLiteral il) => il.value > 0 ? 4.0f / il.value.to!float : 0.0f,
            (DurationLiteral dl)
            {
                import std.math : pow;
                float n = dl.denominator > 0 ? 4.0f / dl.denominator.to!float : 0.0f;
                return n * (2.0f - pow(0.5f, dl.dot.to!float));
            },
            (TimeLiteral tl) => _timeEval(startTick, tl),
            (UnaryExpression ue)
            {
                final switch (ue.op.kind)
                {
                case OperatorKind.plus:
                    return +evaluate(startTick, ue.operand);

                case OperatorKind.minus:
                    return -evaluate(startTick, ue.operand);

                case OperatorKind.star:
                case OperatorKind.slash:
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
}

package final class NumericExpressionEvaluator(T)
{
    public this(DiagnosticsHandler handler)
    {
        _diagnosticsHandler = handler;
    }

    public T evaluate(Expression expr)
    {
        assert(expr !is null);
        return expr.visit!(
            (IntegerLiteral il) => il.value,
            (UnaryExpression ue)
            {
                final switch (ue.op.kind)
                {
                case OperatorKind.plus:
                    return +evaluate(ue.operand);

                case OperatorKind.minus:
                    return -evaluate(ue.operand);

                case OperatorKind.star:
                case OperatorKind.slash:
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
                    T r = evaluate(be.right);

                    if (r == 0)
                    {
                        _diagnosticsHandler.divideBy0(be.location);
                        return evaluate(be.left);
                    }
                    else
                    {
                        return evaluate(be.left) / evaluate(be.right);
                    }
                }
            },
            (x)
            {
                _diagnosticsHandler.unexpectedExpressionKind(expr.location, "duration");
                return 0;
            }
        );
    }

    private DiagnosticsHandler _diagnosticsHandler;
}

package final class StringExpressionEvaluator
{
    import std.array : Appender, appender;

    public this(DiagnosticsHandler handler)
    {
        _diagnosticsHandler = handler;
    }

    public string evaluate(Expression expr)
    {
        assert(expr !is null);

        auto str = appender!string();
        evaluate(str, expr);
        return str[];
    }

    public void evaluate(Appender!string str, Expression expr)
    {
        assert(expr !is null);

        expr.visit!(
            (StringLiteral sl)
            {
                str.put(sl.value);
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
}
