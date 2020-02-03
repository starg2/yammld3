
module yammld3.eval;

import std.conv : to;

import yammld3.ast;
import yammld3.common;
import yammld3.diagnostics;

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
        import std.math : pow;
        assert(expr !is null);
    
        final switch (expr.kind)
        {
        case ExpressionKind.integerLiteral:
            auto il = cast(IntegerLiteral)expr;
            return il.value > 0 ? 4.0f / il.value.to!float : 0.0f;
            
        case ExpressionKind.durationLiteral:
            auto dl = cast(DurationLiteral)expr;
            float n = dl.denominator > 0 ? 4.0f / dl.denominator.to!float : 0.0f;
            return n * (2.0f - pow(0.5f, dl.dot.to!float));
            
        case ExpressionKind.timeLiteral:
            return _timeEval(startTick, cast(TimeLiteral)expr);
            
        case ExpressionKind.binaryExpression:
            auto be = cast(BinaryExpression)expr;
            
            if (be.op.kind == OperatorKind.plus)
            {
                return evaluate(startTick, be.left) + evaluate(startTick, be.right);
            }
            else if (be.op.kind == OperatorKind.minus)
            {
                return evaluate(startTick, be.left) - evaluate(startTick, be.right);
            }
            
            goto case;
            
        case ExpressionKind.identifier:
        case ExpressionKind.stringLiteral:
        case ExpressionKind.unaryExpression:
        case ExpressionKind.callExpression:
            _diagnosticsHandler.unexpectedExpressionKind(expr.location, "duration");
            return 0.0f;
        }
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
    
        final switch (expr.kind)
        {
        case ExpressionKind.integerLiteral:
            auto il = cast(IntegerLiteral)expr;
            return il.value;
            
        case ExpressionKind.unaryExpression:
            auto ue = cast(UnaryExpression)expr;
            
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
        
        case ExpressionKind.binaryExpression:
            auto be = cast(BinaryExpression)expr;
            
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
            
        case ExpressionKind.identifier:
        case ExpressionKind.durationLiteral:
        case ExpressionKind.timeLiteral:
        case ExpressionKind.stringLiteral:
        case ExpressionKind.callExpression:
            _diagnosticsHandler.unexpectedExpressionKind(expr.location, "duration");
            return 0;
        }
    }
    
    private DiagnosticsHandler _diagnosticsHandler;
}
