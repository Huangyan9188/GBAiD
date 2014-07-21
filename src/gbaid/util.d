module gbaid.util;

public ulong ucast(int v) {
    return cast(ulong) v & 0xFFFFFFFF;
}

public bool checkBit(int i, int b) {
    return cast(bool) getBit(i, b);
}

public int getBit(int i, int b) {
    return i >> b & 1;
}

public void setBit(ref int i, int b, int n) {
    i = i & ~(1 << b) | (n & 1) << b;
}

public int getBits(int i, int a, int b) {
    return i >> a & (1 << b - a + 1) - 1;
}

public void setBits(ref int i, int a, int b, int n) {
    int mask = (1 << b - a + 1) - 1 << a;
    i = i & ~mask | n << a & mask;
}

public bool carried(int a, int b, int r) {
    return cast(uint) r < cast(uint) a;
}

public bool overflowed(int a, int b, int r) {
    int rn = getBit(r, 31);
    return getBit(a, 31) != rn && getBit(b, 31) != rn;
}

template getSafe(T) {
    public T getSafe(T[] array, int index, T def) {
        if (index < 0 || index >= array.length) {
            return def;
        }
        return array[index];
    }
}

template addAll(K, V) {
    public void addAll(V[K] to, V[K] from) {
        foreach (k; from.byKey()) {
            to[k] = from[k];
        }
    }
}

template removeAll(K, V) {
    public void removeAll(V[K] to, V[K] from) {
        foreach (k; from.byKey()) {
            to.remove(k);
        }
    }
}

public string toString(char[] cs) {
    import std.conv;
    ulong end;
    foreach (i; 0 .. cs.length) {
        if (cs[i] == '\0') {
            end = i;
            break;
        }
    }
    return to!string(cs[0 .. end]);
}
