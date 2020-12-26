// Copyright (c) 2020 Starg.
// SPDX-License-Identifier: BSD-3-Clause

module yammld3.priorspec;

import std.algorithm.comparison : clamp;
import std.algorithm.sorting;
import std.conv : to;
import std.range;
import std.traits : isFloatingPoint;
import std.typecons : isTuple, Tuple;

package interface PriorSpec(T)
{
    bool expired(int noteCount, float time);
    void apply(ref T value, int noteCount, float time);
}

private auto getKey(T)(T p)
{
    static if (isTuple!T)
    {
        return p[0];
    }
    else
    {
        return p;
    }
}

private bool lessKeyThan(T, U)(T a, U b)
{
    static if (isFloatingPoint!(typeof(a.getKey())) || isFloatingPoint!(typeof(b.getKey())))
    {
        import std.math : cmp;
        return cmp(a.getKey(), b.getKey()) < 0;
    }
    else
    {
        return a.getKey() < b.getKey();
    }
}

private alias SortedPairRange(T, U) = SortedRange!(Tuple!(T, U)[], lessKeyThan);

private U interpolateNone(T, U)(SortedPairRange!(T, U) r, T key)
{
    static assert(!isFloatingPoint!T, "floating point keys are not safe");
    auto er = r.equalRange(key);

    if (er.empty)
    {
        return 0;
    }
    else
    {
        return er.back[1];
    }
}

private U interpolateDiscrete(T, U)(SortedPairRange!(T, U) r, T key)
{
    auto tr = r.trisect(key);

    if (tr[1].empty)
    {
        if (tr[0].empty)
        {
            return 0;
        }
        else
        {
            return tr[0].back[1];
        }
    }
    else
    {
        return tr[1].back[1];
    }
}

private U interpolateLinear(T, U)(SortedPairRange!(T, U) r, T key)
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
                return tr[2].front[1];
            }
        }
        else
        {
            if (tr[2].empty)
            {
                return tr[0].back[1];
            }
            else
            {
                auto ax = tr[0].back[0];
                auto ay = tr[0].back[1];
                auto bx = tr[2].front[0];
                auto by = tr[2].front[1];
                auto cx = key;

                assert(ax != bx);
                return (ay + (by - ay) * (cx - ax) / (bx - ax)).to!U;
            }
        }
    }
    else
    {
        return tr[1].back[1];
    }
}

package final class OffsetPriorSpec(T) : PriorSpec!T
{
    public this(T value)
    {
        _value = value;
    }

    public override bool expired(int noteCount, float time)
    {
        return false;
    }

    public override void apply(ref T value, int noteCount, float time)
    {
        value += _value;
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

    public override void apply(ref T value, int noteCount, float time)
    {
        value += (_minValue + _pRNG.front * (_maxValue - _minValue)).to!T.clamp(_minValue, _maxValue);
        _pRNG.popFront();
    }

    private RNG* _pRNG;
    private T _minValue;
    private T _maxValue;
}

package final class NormalRandomPriorSpec(RNG, T) : PriorSpec!T
{
    public this(RNG* pRNG, T mean, float stdDev)
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

    public override void apply(ref T value, int noteCount, float time)
    {
        import std.math : cos, log, PI, sqrt;

        float x = _pRNG.front;
        _pRNG.popFront();
        float y = _pRNG.front;
        _pRNG.popFront();

        float z = sqrt(-2.0f * log(x)) * cos(2.0f * PI * y);
        value += (z * _stdDev + _mean).to!T;
    }

    private RNG* _pRNG;
    private T _mean;
    private float _stdDev;
}

package final class OnNotePriorSpec(T) : PriorSpec!T
{
    public this(int startCount, Tuple!(int, T)[] values)
    {
        this(startCount, 1, values);
    }

    public this(int startCount, int repeatCount, Tuple!(int, T)[] values)
    {
        _startCount = startCount;
        _repeatCount = repeatCount;
        _values = values.dup.sort!lessKeyThan();
    }

    public override bool expired(int noteCount, float time)
    {
        return _values.empty || (_values.back[0] + 1) * _repeatCount <= noteCount - _startCount;
    }

    public override void apply(ref T value, int noteCount, float time)
    {
        if (!_values.empty)
        {
            value += interpolateNone!(int, T)(_values, (noteCount - _startCount) % (_values.back[0] + 1));
        }
    }

    private int _startCount;
    private int _repeatCount;
    private SortedPairRange!(int, T) _values;
}

package final class OnTimePriorSpec(T) : PriorSpec!T
{
    public this(float startTime, Tuple!(float, T)[] values, bool linearInterpolation)
    {
        _startTime = startTime;
        _values = values.dup.sort!lessKeyThan();
        _linearInterpolation = linearInterpolation;
    }

    public override bool expired(int noteCount, float time)
    {
        return _values.empty || _values.back[0] < time - _startTime;
    }

    public override void apply(ref T value, int noteCount, float time)
    {
        if (_linearInterpolation)
        {
            value += interpolateLinear!(float, T)(_values, time - _startTime);
        }
        else
        {
            value += interpolateDiscrete!(float, T)(_values, time - _startTime);
        }
    }

    private float _startTime;
    private SortedPairRange!(float, T) _values;
    private bool _linearInterpolation;
}

package final class ClampPriorSpec(T) : PriorSpec!T
{
    public this(T minValue, T maxValue)
    {
        _minValue = minValue;
        _maxValue = maxValue;
    }

    public override bool expired(int noteCount, float time)
    {
        return false;
    }

    public override void apply(ref T value, int noteCount, float time)
    {
        value = value.clamp(_minValue, _maxValue);
    }

    private T _minValue;
    private T _maxValue;
}
