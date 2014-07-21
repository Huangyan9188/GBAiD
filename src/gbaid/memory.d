module gbaid.memory;

import std.string;
import std.file;
import std.path;

public immutable uint BYTES_PER_KIB = 1024;
public immutable uint BYTES_PER_MIB = BYTES_PER_KIB * BYTES_PER_KIB;

public interface Memory {
    ulong getCapacity();

    byte getByte(uint address);

    void setByte(uint address, byte b);

    short getShort(uint address);

    void setShort(uint address, short s);

    int getInt(uint address);

    void setInt(uint address, int i);

    long getLong(uint address);

    void setLong(uint address, long l);
}

public class ROM : Memory {
    protected int[] memory;

    public this(string file, uint maxSize) {
        try {
            this(cast(int[]) read(expandTilde(file), maxSize));
        } catch (FileException ex) {
            throw new Exception("Cannot initialize ROM", ex);
        }
    }

    public this(int[] memory) {
        this.memory = memory;
    }

    public ulong getCapacity() {
        return memory.length * 4;
    }

    public byte getByte(uint address) {
        return cast(byte) (memory[address / 4] >> address % 4 * 8 & 0xFF);
    }

    public void setByte(uint address, byte b) {
        throw new ReadOnlyException();
    }

    public short getShort(uint address) {
        address /= 2;
        return cast(short) (memory[address / 2] >> address % 2 * 16 & 0xFFFF);
    }

    public void setShort(uint address, short s) {
        throw new ReadOnlyException();
    }

    public int getInt(uint address) {
        return memory[address / 4];
    }

    public void setInt(uint address, int i) {
        throw new ReadOnlyException();
    }

    public long getLong(uint address) {
        address /= 4;
        return cast(long) memory[address] & 0xFFFFFFFF | cast(long) memory[address + 1] << 32;
    }

    public void setLong(uint address, long l) {
        throw new ReadOnlyException();
    }
}

public class RAM : ROM {
    public this(string file, uint maxByteSize) {
        super(file, maxByteSize);
    }

    public this(int[] memory) {
        super(memory);
    }

    public this(ulong capacity) {
        this(new int[capacity / 4]);
    }

    public override void setByte(uint address, byte b) {
        int wordAddress = address / 4;
        int offset = address % 4 * 8;
        memory[wordAddress] = memory[wordAddress] & ~(0xFF << offset) | (b & 0xFF) << offset;
    }

    public override void setShort(uint address, short s) {
        address /= 2;
        int wordAddress = address / 2;
        int offset = address % 2 * 16;
        memory[wordAddress] = memory[wordAddress] & ~(0xFFFF << offset) | (s & 0xFFFF) << offset;
    }

    public override void setInt(uint address, int i) {
        memory[address / 4] = i;
    }

    public override void setLong(uint address, long l) {
        address /= 4;
        memory[address] = cast(int) l;
        memory[address + 1] = cast(int) (l >> 32);
    }
}

public class ReadOnlyException : Exception {
    public this() {
        super("Memory is read only");
    }
}


public class BadAddressException : Exception {
    public this(uint address) {
        super(format("Invalid address: 0x%X", address));
    }
}
