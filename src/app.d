import std.stdio;
import std.getopt;
import std.string;
import std.file;
import std.path;

import gbaid.system;
import gbaid.graphics;
import gbaid.util;

public void main(string[] args) {
    // Parse comand line arguments
    string bios = null, save = null;
    bool noLoad = false, noSave = false;
    float scale = 2;
    FilteringMode filtering = FilteringMode.NONE;
    getopt(args,
        config.caseSensitive,
        "bios|b", &bios,
        "save|s", &save,
        config.bundling,
        "noload|n", &noLoad,
        "nosave|N", &noSave,
        config.noBundling,
        "scale|r", &scale,
        "filtering|f", &filtering
    );

    // Resolve BIOS
    if (bios is null) {
        writeln("Missing BIOS file path, sepcify with \"-b (path to bios)\"");
        return;
    }
    bios = expandPath(bios);
    if (!exists(bios)) {
        writeln("BIOS file doesn't exist");
        return;
    }

    // Resolve ROM
    string rom = getSafe!string(args, 1, null);
    if (rom is null) {
        writeln("Missing ROM file path, sepcify as last argument");
        return;
    }
    rom = expandPath(rom);
    if (!exists(rom)) {
        writeln("ROM file doesn't exist");
        return;
    }

    // Resolve save
    if (noLoad) {
        save = null;
        writeln("Using new save");
    } else {
        if (save is null) {
            save = setExtension(rom, ".sav");
            writeln("Save path not specified, using default \"" ~ save ~ "\"");
        } else {
            save = expandPath(save);
        }
        if (exists(save)) {
            writeln("Loaded save \"" ~ save ~ "\"");
        } else {
            save = null;
            writeln("Save file not found, using new save");
        }
    }

    // Create Game Pak
    GamePak gamePak = new GamePak(rom, save);

    // Create and configure GBA
    GameBoyAdvance gba = new GameBoyAdvance(bios);
    gba.setGamePak(gamePak);
    gba.setDisplayScale(scale);
    gba.setDisplayFilteringMode(filtering);

    // Run GBA
    gba.run();

    // Save Game Pak save
    if (!noSave) {
        if (save is null) {
            save = setExtension(rom, ".sav");
        }
        gamePak.saveSave(save);
        writeln("Saved save \"" ~ save ~ "\"");
    }

    // TODO:
    //       rewrite more of the graphics in x64
    //       implement optional RTC
}
