
module yammld3.priorspec;

import std.algorithm.sorting;
import std.math : cmp;
import std.range;

package interface PriorSpec(T)
{
    bool expired(int noteCount, float time);
    T getValueFor(int noteCount, float time);
}

package struct KeyValuePair(T, U)
{
    T key;
    U value;
}

private T getKey(T)(T k)
{
    return k;
}

private T getKey(T, U)(KeyValuePair!(T, U) p)
{
    return p.key;
}

private alias lessKeyThan = (a, b) => cmp(a.getKey(), b.getKey()) < 0;

private alias SortedKeyValuePairRange(T, U) = SortedRange!(KeyValuePair!(T, U)[], lessKeyThan);

private U interpolateNone(T, U)(SortedKeyValuePairRange!(T, U) r, T key)
{
    auto er = r.equalRange(key);
    
    if (er.empty)
    {
        return 0;
    }
    else
    {
        return er.back.value;
    }
}

private U interpolateLinear(T, U)(SortedKeyValuePairRange!(T, U) r, T key)
{
    auto tr = r.trisect(key);
    
    if (tr[1].empty)
    {
        if (tr[0].empty)
        {
            if (tr[2].empty)
            {
                return 0;
            }
            else
            {
                return tr[2].front.value;
            }
        }
        else
        {
            if (tr[2].empty)
            {
                return tr[0].back.value;
            }
            else
            {
                auto ax = tr[0].back.key;
                auto ay = tr[0].back.value;
                auto bx = tr[2].front.key;
                auto by = tr[2].front.value;
                auto cx = key;
                
                assert(ax != bx);
                return ay + (by - ay) * (cx - ax) / (bx - ax);
            }
        }
    }
    else
    {
        return tr[1].back.value;
    }
}

package final class ConstantPriorSpec(T) : PriorSpec!T
{
    public this(T value)
    {
        _value = value;
    }
    
    public override bool expired(int noteCount, float time)
    {
        return false;
    }
    
    public override T getValueFor(int noteCount, float time)
    {
        return _value;
    }
    
    private T _value;
}

package final class UniformRandomPriorSpec(RNG, T) : PriorSpec!T
{
    public this(RNG* pRNG, T minValue, T maxValue)
    {
        assert(pRNG !is null);
    
        _pRNG = pRNG;
        _minValue = minValue;
        _maxValue = maxValue;
    }
    
    public override bool expired(int noteCount, float time)
    {
        return false;
    }
    
    public override T getValueFor(int noteCount, float time)
    {
        import std.random : uniform;
        return uniform!"[]"(_minValue, _maxValue, *_pRNG);
    }
    
    private RNG* _pRNG;
    private T _minValue;
    private T _maxValue;
}

package final class NormalRandomPriorSpec(RNG, T) : PriorSpec!T
{
    public this(RNG* pRNG, T mean, T stdDev)
    {
        assert(pRNG !is null);
    
        _pRNG = pRNG;
        _mean = mean;
        _stdDev = stdDev;
    }
    
    public override bool expired(int noteCount, float time)
    {
        return false;
    }
    
    public override T getValueFor(int noteCount, float time)
    {
        import std.math : cos, log, PI, sqrt;
        import std.random : uniform;
        
        float x = uniform!"()"(0.0f, 1.0f, *_pRNG);
        float y = uniform!"()"(0.0f, 1.0f, *_pRNG);
        
        float z = sqrt(-2.0f * log(x)) * cos(2.0f * PI * y);
        return z * _stdDev + _mean;
    }
    
    private RNG* _pRNG;
    private T _mean;
    private T _stdDev;
}

package final class OnNotePriorSpec(T) : PriorSpec!T
{
    public this(int startCount, KeyValuePair!(int, T)[] values)
    {
        _startCount = startCount;
        _values = values.sort!lessKeyThan();
    }

    public override bool expired(int noteCount, float time)
    {
        return _values.empty || _values.back.key < noteCount - _startCount;
    }
    
    public override T getValueFor(int noteCount, float time)
    {
        return interpolateNone(_values, noteCount - _startCount);
    }
    
    private int _startCount;
    private SortedKeyValuePairRange!(int, T) _values;
}

package final class OnTimePriorSpec(T) : PriorSpec!T
{
    public this(float startTime, KeyValuePair!(float, T)[] values)
    {
        _startTime = startTime;
        _values = values.sort!lessKeyThan();
    }

    public override bool expired(int noteCount, float time)
    {
        return _values.empty || _values.back.key < time - _starttime;
    }
    
    public override T getValueFor(int noteCount, float time)
    {
        return interpolateNone(_values, time - _startTime);
    }
    
    private float _startTime;
    private SortedKeyValuePairRange!(float, T) _values;
}

package final class OnTimeLinearPriorSpec(T) : PriorSpec!T
{
    public this(float startTime, KeyValuePair!(float, T)[] values)
    {
        _startTime = startTime;
        _values = values.sort!lessKeyThan();
    }

    public override bool expired(int noteCount, float time)
    {
        return _values.empty || _values.back.key < time - _starttime;
    }
    
    public override T getValueFor(int noteCount, float time)
    {
        return interpolateLinear(_values, time - _startTime);
    }
    
    private float _startTime;
    private SortedKeyValuePairRange!(float, T) _values;
}
