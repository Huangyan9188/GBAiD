module gbaid.memory;

import core.thread;
import core.time;
import core.atomic;

import std.stdio;
import std.string;
import std.file;

import gbaid.util;

public immutable uint BYTES_PER_KIB = 1024;
public immutable uint BYTES_PER_MIB = BYTES_PER_KIB * BYTES_PER_KIB;

public abstract class Memory {
    public abstract ulong getCapacity();

    public abstract void[] getArray(uint address);

    public abstract void* getPointer(uint address);

    public abstract byte getByte(uint address);

    public abstract void setByte(uint address, byte b);

    public abstract short getShort(uint address);

    public abstract void setShort(uint address, short s);

    public abstract int getInt(uint address);

    public abstract void setInt(uint address, int i);

    public abstract bool compareAndSet(uint address, int expected, int update);
}

public class ROM : Memory {
    protected shared void[] memory;

    protected this(ulong capacity) {
        this.memory = new shared byte[capacity];
    }

    public this(void[] memory) {
        this(memory.length);
        this.memory[] = memory[];
    }

    public this(string file, uint maxSize) {
        try {
            this(read(file, maxSize));
        } catch (FileException ex) {
            throw new Exception("Cannot initialize ROM", ex);
        }
    }

    public override ulong getCapacity() {
        return memory.length;
    }

    public override void[] getArray(uint address) {
        return cast(void[]) memory[address .. $];
    }

    public override void* getPointer(uint address) {
        return cast(void*) memory.ptr + address;
    }

    public override byte getByte(uint address) {
        return (cast(byte[]) memory)[address];
    }

    public override void setByte(uint address, byte b) {
    }

    public override short getShort(uint address) {
        return (cast(short[]) memory)[address >> 1];
    }

    public override void setShort(uint address, short s) {
    }

    public override int getInt(uint address) {
        return (cast(int[]) memory)[address >> 2];
    }

    public override void setInt(uint address, int i) {
    }

    public override bool compareAndSet(uint address, int expected, int update) {
        return false;
    }
}

public class RAM : ROM {
    public this(ulong capacity) {
        super(capacity);
    }

    public this(void[] memory) {
        super(memory);
    }

    public this(string file, uint maxByteSize) {
        super(file, maxByteSize);
    }

    public override void setByte(uint address, byte b) {
        (cast(byte[]) memory)[address] = b;
    }

    public override void setShort(uint address, short s) {
        (cast(short[]) memory)[address >> 1] = s;
    }

    public override void setInt(uint address, int i) {
        (cast(int[]) memory)[address >> 2] = i;
    }

    public override bool compareAndSet(uint address, int expected, int update) {
        return cas(cast(shared int*) getPointer(address), expected, update);
    }
}

public class Flash : RAM {
    private static immutable uint PANASONIC_64K_ID = 0x1B32;
    private static immutable uint SANYO_128K_ID = 0x1362;
    private static immutable uint DEVICE_ID_ADDRESS = 0x1;
    private static immutable uint FIRST_CMD_ADDRESS = 0x5555;
    private static immutable uint SECOND_CMD_ADDRESS = 0x2AAA;
    private static immutable uint FIRST_CMD_START_BYTE = 0xAA;
    private static immutable uint SECOND_CMD_START_BYTE = 0x55;
    private static immutable uint ID_MODE_START_CMD_BYTE = 0x90;
    private static immutable uint ID_MODE_STOP_CMD_BYTE = 0xF0;
    private static immutable uint ERASE_CMD_BYTE = 0x80;
    private static immutable uint ERASE_ALL_CMD_BYTE = 0x10;
    private static immutable uint ERASE_SECTOR_CMD_BYTE = 0x30;
    private static immutable uint WRITE_BYTE_CMD_BYTE = 0xA0;
    private static immutable uint SWITCH_BANK_CMD_BYTE = 0xB0;
    private static TickDuration WRITE_TIMEOUT = 10;
    private static TickDuration ERASE_SECTOR_TIMEOUT = 500;
    private static TickDuration ERASE_ALL_TIMEOUT = 500;
    private uint deviceID;
    private Mode mode = Mode.NORMAL;
    private uint cmdStage = 0;
    private bool timedCMD = false;
    private TickDuration cmdStartTime;
    private TickDuration cmdTimeOut;
    private uint eraseSectorTarget;
    private uint sectorOffset = 0;

    static this() {
        WRITE_TIMEOUT = TickDuration.from!"msecs"(10);
        ERASE_SECTOR_TIMEOUT = TickDuration.from!"msecs"(500);
        ERASE_ALL_TIMEOUT = TickDuration.from!"msecs"(500);
    }

    public this(ulong capacity) {
        super(capacity);
        idChip();
    }

    public this(void[] memory) {
        super(memory);
        idChip();
    }

    public this(string file, uint maxByteSize) {
        super(file, maxByteSize);
        idChip();
    }

    private void idChip() {
        if (memory.length > 64 * BYTES_PER_KIB) {
            deviceID = SANYO_128K_ID;
        } else {
            deviceID = PANASONIC_64K_ID;
        }
    }

    public override byte getByte(uint address) {
        if (mode == Mode.ID && address <= DEVICE_ID_ADDRESS) {
            return cast(byte) (deviceID >> ((address & 0b1) << 3));
        }
        return super.getByte(address + sectorOffset);
    }

    public override void setByte(uint address, byte b) {
        uint value = b & 0xFF;
        // Handle command time-outs
        if (timedCMD && TickDuration.currSystemTick >= cmdTimeOut) {
            endCMD();
        }
        // Handle commands completions
        switch (mode) {
            case Mode.ERASE_ALL:
                if (address == 0x0 && value == 0xFF) {
                    endCMD();
                }
                break;
            case Mode.ERASE_SECTOR:
                if (address == eraseSectorTarget && value == 0xFF) {
                    endCMD();
                }
                break;
            case Mode.WRITE_BYTE:
                super.setByte(address + sectorOffset, b);
                endCMD();
                break;
            default:
        }
        // Handle command initialization and execution
        if (address == FIRST_CMD_ADDRESS && value == FIRST_CMD_START_BYTE) {
            cmdStage = 1;
        } else if (cmdStage == 1) {
            if (address == SECOND_CMD_ADDRESS && value == SECOND_CMD_START_BYTE) {
                cmdStage = 2;
            } else {
                cmdStage = 0;
            }
        } else if (cmdStage == 2) {
            cmdStage = 0;
            // execute
            if (address == FIRST_CMD_ADDRESS) {
                switch (value) {
                    case ID_MODE_START_CMD_BYTE:
                        mode = Mode.ID;
                        break;
                    case ID_MODE_STOP_CMD_BYTE:
                        mode = Mode.NORMAL;
                        break;
                    case ERASE_CMD_BYTE:
                        mode = Mode.ERASE;
                        break;
                    case ERASE_ALL_CMD_BYTE:
                        if (mode == Mode.ERASE) {
                            mode = Mode.ERASE_ALL;
                            startTimedCMD(ERASE_ALL_TIMEOUT);
                            erase(0x0, cast(uint) getCapacity());
                        }
                        break;
                    case WRITE_BYTE_CMD_BYTE:
                        mode = Mode.WRITE_BYTE;
                        startTimedCMD(WRITE_TIMEOUT);
                        break;
                    case SWITCH_BANK_CMD_BYTE:
                        if (deviceID == SANYO_128K_ID) {
                            sectorOffset = (b & 0b1) << 16;
                        }
                        break;
                    default:
                }
            } else if (!(address & 0xFF0FFF) && value == ERASE_SECTOR_CMD_BYTE && mode == Mode.ERASE) {
                mode = Mode.ERASE_SECTOR;
                eraseSectorTarget = address;
                startTimedCMD(ERASE_SECTOR_TIMEOUT);
                erase(address, 4 * BYTES_PER_KIB);
            }
        }
    }

    private void startTimedCMD(TickDuration timeOut) {
        cmdStartTime = TickDuration.currSystemTick();
        cmdTimeOut = cmdStartTime + timeOut;
        timedCMD = true;
    }

    private void endCMD() {
        mode = Mode.NORMAL;
        timedCMD = false;
    }

    private void erase(uint address, uint size) {
        foreach (i; address .. address + size) {
            super.setByte(i, cast(byte) 0xFF);
        }
    }

    public override short getShort(uint address) {
        throw new UnsupportedMemoryWidthException(address, 2);
    }

    public override void setShort(uint address, short s) {
        throw new UnsupportedMemoryWidthException(address, 2);
    }

    public override int getInt(uint address) {
        throw new UnsupportedMemoryWidthException(address, 4);
    }

    public override void setInt(uint address, int i) {
        throw new UnsupportedMemoryWidthException(address, 4);
    }

    public override bool compareAndSet(uint address, int expected, int update) {
        throw new UnsupportedMemoryOperationException("compareAndSet");
    }

    private static enum Mode {
        NORMAL,
        ID,
        ERASE,
        ERASE_ALL,
        ERASE_SECTOR,
        WRITE_BYTE,
    }
}

public class EEPROM : RAM {
    private Mode mode = Mode.NORMAL;
    private int validCMD = false;
    private int targetAddress = 0;
    private int currentAddressBit = 0, currentReadBit = 0;
    private int[3] writeBuffer = new int[3];

    public this(ulong capacity) {
        super(capacity);
    }

    public this(void[] memory) {
        super(memory);
    }

    public this(string file, uint maxByteSize) {
        super(file, maxByteSize);
    }

    public override byte getByte(uint address) {
        throw new UnsupportedMemoryWidthException(address, 1);
    }

    public override void setByte(uint address, byte b) {
        throw new UnsupportedMemoryWidthException(address, 1);
    }

    public override short getShort(uint address) {
        if (mode == Mode.WRITE) {
            // get write address and offset in write buffer
            int actualAddress = void;
            int bitOffset = void;
            if (currentAddressBit > 73) {
                actualAddress = targetAddress >>> 14;
                bitOffset = 14;
            } else {
                actualAddress = targetAddress >>> 23;
                bitOffset = 6;
            }
            // get data to write from buffer
            long toWrite = 0;
            foreach (int i; 0 .. 64) {
                toWrite |= ucast(getBit(writeBuffer[i + bitOffset >> 5], i + bitOffset & 31)) << 63 - i;
            }
            // write data
            super.setInt(actualAddress, cast(int) toWrite);
            super.setInt(actualAddress + 4, cast(int) (toWrite >>> 32));
            // end write mode
            mode = Mode.NORMAL;
            validCMD = false;
            targetAddress = 0;
            currentAddressBit = 0;
            currentReadBit = 0;
            // return ready
            return 1;
        } else if (mode == Mode.READ) {
            // get data
            short data = void;
            if (currentReadBit < 4) {
                // first 4 bits are 0
                data = 0;
            } else {
                // get read address depending on amount of bits received
                int actualAddress = void;
                if (currentAddressBit > 9) {
                    actualAddress = targetAddress >>> 14;
                } else {
                    actualAddress = targetAddress >>> 23;
                }
                actualAddress += 7 - (currentReadBit - 4 >> 3);
                // get the data bit
                data = cast(short) getBit(super.getByte(actualAddress), 7 - (currentReadBit - 4 & 7));
            }
            // end read mode on last bit
            if (currentReadBit == 67) {
                mode = Mode.NORMAL;
                validCMD = false;
                targetAddress = 0;
                currentAddressBit = 0;
                currentReadBit = 0;
            } else {
                // increment current read bit and save address
                currentReadBit++;
            }
            return data;
        }
        return 0;
    }

    public override void setShort(uint address, short s) {
        // get relevant bit
        int bit = s & 0b1;
        // if in write mode, buffer the bit
        if (mode == Mode.WRITE) {
            setBit(writeBuffer[currentAddressBit - 2 >> 5],  currentAddressBit - 2 & 31, bit);
        }
        // then process as command or address bit
        if (currentAddressBit == 0) {
            // first command bit
            if (bit == 0b1) {
                // mark as valid if it corresponds to a command
                validCMD = true;
            }
        } else if (currentAddressBit == 1) {
            // second command bit
            if (validCMD) {
                // set mode if we have a proper command
                mode = cast(Mode) bit;
            }
        } else if (validCMD && currentAddressBit < 16) {
            // set address bit if command was valid
            setBit(targetAddress, 33 - currentAddressBit, bit);
        }
        // increment bit count and save address
        currentAddressBit++;
    }

    public override int getInt(uint address) {
        throw new UnsupportedMemoryWidthException(address, 4);
    }

    public override void setInt(uint address, int i) {
        throw new UnsupportedMemoryWidthException(address, 4);
    }

    public override bool compareAndSet(uint address, int expected, int update) {
        throw new UnsupportedMemoryOperationException("compareAndSet");
    }

    private static enum Mode {
        NORMAL = 2,
        READ = 1,
        WRITE = 0
    }
}

public class NullMemory : Memory {
    public override ulong getCapacity() {
        return 0;
    }

    public override void[] getArray(uint address) {
        return null;
    }

    public override void* getPointer(uint address) {
        return null;
    }

    public override byte getByte(uint address) {
        return 0;
    }

    public override void setByte(uint address, byte b) {
    }

    public override short getShort(uint address) {
        return 0;
    }

    public override void setShort(uint address, short s) {
    }

    public override int getInt(uint address) {
        return 0;
    }

    public override void setInt(uint address, int i) {
    }

    public override bool compareAndSet(uint address, int expected, int update) {
        return false;
    }
}

public class ReadOnlyException : Exception {
    public this(uint address) {
        super(format("Memory is read only: 0x%X", address));
    }
}

public class UnsupportedMemoryWidthException : Exception {
    public this(uint address, uint badByteWidth) {
        super(format("Attempted to access 0x%X with unsupported memory width of %s bytes", address, badByteWidth));
    }
}

public class BadAddressException : Exception {
    public this(uint address) {
        super(format("Invalid address: 0x%X", address));
    }
}

public class UnsupportedMemoryOperationException : Exception {
    public this(string operation) {
        super(format("Unsupported operation: %s", operation));
    }
}

/*
 Format:
    Header:
        1 int: number of memory objects (n)
        n int pairs:
            1 int: memory type ID
                0: ROM
                1: RAM
                2: Flash
                3: EEPROM
            1 int: memory capacity in bytes (c)
    Body:
        n byte groups:
            c bytes: memory
 */

public Memory[] loadFromFile(string filePath) {
    Memory fromTypeID(int id, void[] contents) {
        final switch (id) {
            case 0:
                return new ROM(contents);
            case 1:
                return new RAM(contents);
            case 2:
                return new Flash(contents);
            case 3:
                return new EEPROM(contents);
        }
    }
    // open file in binary read
    File file = File(filePath, "rb");
    // read size of header
    int[1] lengthBytes = new int[1];
    file.rawRead(lengthBytes);
    int length = lengthBytes[0];
    // read type and capacity information
    int[] header = new int[length * 2];
    file.rawRead(header);
    // read memory objects
    Memory[] memories = new Memory[length];
    for (int i = 0; i < length; i++) {
        int pair = i * 2;
        int type = header[pair];
        int capacity = header[pair + 1];
        void[] contents = new byte[capacity];
        file.rawRead(contents);
        memories[i] = fromTypeID(type, contents);
    }
    return memories;
    // closing is done automatically
}

public void saveToFile(string filePath, Memory[] memories ...) {
    int toTypeID(Memory memory) {
        // order matters because of inheritance, check subclasses first
        if (cast(EEPROM) memory) {
            return 3;
        }
        if (cast(Flash) memory) {
            return 2;
        }
        if (cast(RAM) memory) {
            return 1;
        }
        if (cast(ROM) memory) {
            return 0;
        }
        throw new Exception("Unsupported memory type: " ~ typeid(memory).name);
    }
    // build the header
    int length = cast(int) memories.length;
    int[] header = new int[1 + length * 2];
    header[0] = length;
    foreach (int i, Memory memory; memories) {
        int pair = 1 + i * 2;
        header[pair] = toTypeID(memory);
        header[pair + 1] = cast(int) memory.getCapacity();
    }
    // open the file in binary write mode
    File file = File(filePath, "wb");
    // write the header
    file.rawWrite(header);
    // write the rest of the memory objects
    foreach (Memory memory; memories) {
        file.rawWrite(memory.getArray(0));
    }
    // closing is done automatically
}
