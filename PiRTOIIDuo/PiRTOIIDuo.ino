/*
//////////////////////////////////////////////////////////////////////////////////////////
//
//                       PiRTO II DUO Flash MultiCART by Andrea Ottaviani 2024
//
//////////////////////////////////////////////////////////////////////////////////////////
//
//  Intellivision flash multicart based on Raspberry Pico2 board -
//  New PiRTO II version with JLP and savegame support
//  More info on https://github.com/aotta/ 
//  
// ***************************************************************************************
//   This upgrade is dedicated to Mariella, with love and gratitude  
//   for trusting me and encouraging me to never give up
// ***************************************************************************************
//
//  v.1.00 - First release 27/12/2025
*/

//#define intydebug // for debug print on intyscreen
#define SD_BOARD 
//#define DEFAULT_BOARD 0

#include "hardware/gpio.h"
#include "pico/platform.h"
#include "pico/stdlib.h"
#include "hardware/vreg.h"
#include "pico/multicore.h"
#include "hardware/flash.h"
#include "hardware/sync.h"
#include "string.h"
#include "rom.h"
#include "dir_entry.hpp"
// include for Flash files
#include "SPI.h"
#include "SD.h"

// file system object from SdFat
File file;
File flashFile;
    

// Pico pin usage definitions
#define B0_PIN    0
#define B1_PIN    1
#define B2_PIN    2
#define B3_PIN    3
#define B4_PIN    4
#define B5_PIN    5
#define B6_PIN    6
#define B7_PIN    7
#define F0_PIN    8
#define F1_PIN    9
#define F2_PIN    10
#define F3_PIN    11
#define F4_PIN    12
#define F5_PIN    13
#define F6_PIN    14
#define F7_PIN    15
#define B0_PIN_MASK     0x00000001L     // gpio 0
#define B1_PIN_MASK     0x00000002L
#define B2_PIN_MASK     0x00000004L
#define B3_PIN_MASK     0x00000008L
#define B4_PIN_MASK     0x00000010L
#define B5_PIN_MASK     0x00000020L
#define B6_PIN_MASK     0x00000040L
#define B7_PIN_MASK     0x00000080L
#define F0_PIN_MASK     0x00000100L
#define F1_PIN_MASK     0x00000200L
#define F2_PIN_MASK     0x00000400L
#define F3_PIN_MASK     0x00000800L
#define F4_PIN_MASK     0x00001000L
#define F5_PIN_MASK     0x00002000L
#define F6_PIN_MASK     0x00004000L
#define F7_PIN_MASK     0x00008000L     // gpio 15 
#define RST_PIN   20
#define LED_PIN   25
#define RST_PIN_MASK    0x00100000L // gpio 20
#define LED_PIN_MASK    0x02000000L // gpio 25

// Pico pin usage masks

#ifdef DEFAULT_BOARD
  #define BDIR_PIN  16
  #define BC2_PIN   17
  #define BC1_PIN   18
  #define MSYNC_PIN 19
  #define BDIR_PIN_MASK   0x00010000L // gpio 16
  #define BC2_PIN_MASK    0x00020000L // gpio 17
  #define BC1_PIN_MASK    0x00040000L // gpio 18
  #define MSYNC_PIN_MASK  0x00080000L // gpio 19
  // Aggregate Pico pin usage masks
  #define ALL_GPIO_MASK  	0x021FFFFFL
#else
#ifdef SD_BOARD
   #define MSYNC_PIN 21
   #define BDIR_PIN  22
   #define BC1_PIN   26
   #define BC2_PIN   27
   
   // SD
   #define SD_MISO   16
   #define SD_CS     17
   #define SD_SCK    18
   #define SD_MOSI   19
   #define MSYNC_PIN_MASK  0x00200000L     // gpio 21
   #define BDIR_PIN_MASK   0x00400000L     // gpio 22
   #define BC1_PIN_MASK    0x04000000L     // gpio 26
   #define BC2_PIN_MASK    0x08000000L     // gpio 27
#endif
#endif



  #define BX_PIN_MASK      (B0_PIN_MASK | B1_PIN_MASK | B2_PIN_MASK | B3_PIN_MASK | B4_PIN_MASK | B5_PIN_MASK | B6_PIN_MASK | B7_PIN_MASK)
   #define FX_PIN_MASK     (F0_PIN_MASK | F1_PIN_MASK | F2_PIN_MASK | F3_PIN_MASK | F4_PIN_MASK | F5_PIN_MASK | F6_PIN_MASK | F7_PIN_MASK)
   #define BC1e2_PIN_MASK  (BC1_PIN_MASK | BC2_PIN_MASK)
   #define DATA_PIN_MASK   (BX_PIN_MASK | FX_PIN_MASK)
   #define BUS_STATE_MASK  (BDIR_PIN_MASK | BC1_PIN_MASK | BC2_PIN_MASK)
   #define ALWAYS_IN_MASK  (BUS_STATE_MASK | MSYNC_PIN_MASK)
   #define ALWAYS_OUT_MASK (LED_PIN_MASK|RST_PIN_MASK )


#define SET_DATA_MODE_OUT   gpio_set_dir_out_masked(DATA_PIN_MASK)
#define SET_DATA_MODE_IN    gpio_set_dir_in_masked(DATA_PIN_MASK)

#define resetLow()  gpio_set_dir(RST_PIN,true); gpio_put(RST_PIN,true); //  Pirto to INTV BUS ; RST Output set to 0
#define resetHigh() gpio_set_dir(RST_PIN,true); gpio_put(RST_PIN,false); // RST is INPUT; B->A, INTV BUS to TEENSY

// Inty bus values (BC1+BC2+BDIR) GPIO 26-27-22

#define BUS_NACT  0b000  //0
#define BUS_BAR   0b001  //1
#define BUS_IAB   0b010  //2
#define BUS_DWS   0b011  //3
#define BUS_ADAR  0b100  //4
#define BUS_DW    0b101  //5
#define BUS_DTB   0b110  //6
#define BUS_INTAK 0b111  //7

#define JLP_CRC_POLY 0xAD52

unsigned char busLookup[8];

char RBLo,RBHi;
#define BINLENGTH  1024*218//65536L
#define RAMSIZE  0x2000
#define FLASHSIZE  0x1800  //xx row da 96 0x1800 poi rimettere!!!

uint16_t ROM[BINLENGTH];
uint16_t RAM[RAMSIZE];

#define maxHacks 32
uint16_t HACK[maxHacks];
uint16_t HACK_CODE[maxHacks];

char curPath[256];
char path[256];
unsigned char files[255*70] = {0}; // 255*64 poi rimettere!!!!!!!!!!
unsigned char nomefiles[32*25] = {0};
int fileda=0,filea=0;
volatile char cmd=0;
char errorBuf[40];
bool cmd_executing=false;
volatile bool gameloaded=false;
volatile bool JLPOn=false;
volatile bool pagingOn=false;
volatile bool FlashingOn=false;
volatile unsigned int parallelBus2;
volatile uint8_t curBank;
volatile uint8_t curPage2;
unsigned int romLen;
volatile unsigned int ramfrom = 0;
volatile unsigned int ramto =   0;
unsigned int mapfrom[80];
unsigned int mapto[80];
unsigned int maprom[80];
int mapdelta[80];
unsigned int mapsize[80];
unsigned int addrto[80];
unsigned int RAMused = 0;
volatile bool RAM8 = false;
unsigned int tipo[80];  // 0-rom / 1-page / 2-ram
unsigned int page[80];  // page number
uint8_t curPage[16];
bool segmentedPage[16];


unsigned int slot;
// Variabili globali per il conteggio degli slot
unsigned int Slot0 = 0;  // Conteggio slot con tipo[] = 0
unsigned int Slot1 = 0;  // Conteggio slot con tipo[] = 1
int hacks;

int base=0x17f;

uint32_t selectedfile_size;    // BIN file size
char flashFilename[80];         // for check if directory
int lenfilename; 
char tiposcelta[9];
bool pressed=false;


////////////////////////////////////////////////////////////////////////////////////
//                     RESET
////////////////////////////////////////////////////////////////////////////////////
void resetCart() {
  gpio_init(MSYNC_PIN);
  gpio_set_dir(MSYNC_PIN,false);
  gpio_set_pulls(MSYNC_PIN,false,true);
  gpio_put(LED_PIN,false);
  resetHigh();
   sleep_ms(30);  // was 20 for Model II; 30 works for both
   resetLow();
  //sleep_ms(3);  // was 2 for Model II; 3 works for both
 
  //while ((gpio_get(MSYNC_PIN)==1)) ;
    
  sleep_ms(1);  // was 1 for Model II; 
  resetHigh();
  memset(curPage,0,sizeof(curPage));
  memset(segmentedPage,0,sizeof(segmentedPage));
  
  gpio_put(LED_PIN,true);
}


/*
 Theory of Operation
 -------------------
 Inty sends command to mcu on cart by writing to 50000 (CMD), 50001 (parameter) and menu (50002-50641) 
 Inty must be running from RAM when it sends a command, since the mcu on the cart will
 go away at that point. Inty polls 50001 until it reads $1.
*/

#pragma GCC push_options
#pragma GCC optimize ("O3")


/////////////////////////////////////////////////
void __time_critical_func(setup1()) {   //HandleBUS()
  unsigned int lastBusState, busState1;
  unsigned int busSt1, busSt2;
  unsigned int parallelBus;

  
//from data bus routine
  bool deviceAddress = false; 
  unsigned int dataOut;
  unsigned int dataWrite=0;
  unsigned char busBit;
  uint8_t seg;
  uint16_t curCRC = 0;

  // multicore_lockout_victim_init();	

  randomSeed(millis());
 

  sleep_ms(480);
  busState1 = BUS_NACT;
  lastBusState = BUS_NACT;
  
  dataOut=0;

    gpio_set_dir_in_masked(ALWAYS_IN_MASK);
    gpio_set_dir_out_masked(ALWAYS_OUT_MASK);
 
    // Initial conditions
    SET_DATA_MODE_IN;
   memset(curPage,0,sizeof(curPage));
  
while(1) {
    // Wait for the bus state to change
    
  do {
    } while (!((gpio_get_all() ^ lastBusState) & BUS_STATE_MASK));
    // We detected a change, but reread the bus state to make sure that all three pins have settled
     lastBusState = gpio_get_all();

      busState1 = ((lastBusState & BC1_PIN_MASK) >> (BC1_PIN - 2)) |
         ((lastBusState & BC2_PIN_MASK) >> (BC2_PIN - 1)) |
         ((lastBusState & BDIR_PIN_MASK) >> BDIR_PIN);

    busBit = busLookup[busState1];
    // Avoiding switch statements here because timing is critical and needs to be deterministic
    if (!busBit)
    {
      // -----------------------
      // DTB
      // -----------------------
      // DTB needs to come first since its timing is critical.  The CP-1600 expects data to be
      // placed on the bus early in the bus cycle (i.e. we need to get data on the bus quickly!)
	    if (deviceAddress)
      {
        // The data was prefetched during BAR/ADAR.  There isn't nearly enough time to fetch it here.
        // We can just output it.
        SET_DATA_MODE_OUT;
        gpio_put_masked(DATA_PIN_MASK,dataOut);
        asm inline ("nop;nop;nop;nop;nop;");
  
            //sukkopera 
       while((gpio_get_all() & BC1e2_PIN_MASK) == BC1e2_PIN_MASK) ;

       SET_DATA_MODE_IN;
      }
     }
    else
    {
      busBit >>= 1;
      if (!busBit)
      {
        // -----------------------
        // BAR, ADAR
        // -----------------------
	    if (busState1==BUS_ADAR) {
	     
        if (deviceAddress)  
      		{
        // The data was prefetched during BAR/ADAR.  There isn't nearly enough time to fetch it here.
        // We can just output it.
       
       	SET_DATA_MODE_OUT;
        gpio_put_masked(DATA_PIN_MASK,dataOut);
  //      asm inline ("nop;nop;nop;");
  
        while (((gpio_get_all() & BC1_PIN_MASK)>>BC1_PIN)); //wait BC1 go down 
        //asm inline (delWR); //150ns

         SET_DATA_MODE_IN;
        
      		}
	    }
        /// ELSE is BAR   
        // Prefetch data here because there won't be enough time to get it during DTB.
        // However, we can't take forever because of all the time we had to wait for
        // the address to appear on the bus.
        // We have to wait until the address is stable on the bus
        // waiting bus is stable 66 nop at 200mhz is ok/85 at 240
       
        SET_DATA_MODE_IN;
          parallelBus=0;
        while(((parallelBus=gpio_get_all()) & BDIR_PIN_MASK));  // wait DIR go low for finish BAR cycle 
       asm inline("nop;nop;nop;nop;");
       //asm inline (delRD); //150ns
    
      parallelBus = gpio_get_all()& 0xFFFF; 
      parallelBus2=parallelBus; //poivia
   // Load data for DTB here to save time

      deviceAddress = false;
      if (((parallelBus>=0x8000)&&(parallelBus<=0x9fff))&&(JLPOn)) {  
            deviceAddress = true;
            dataOut=RAM[parallelBus-0x8000];
        if ((parallelBus>=0x802d)&&(parallelBus<=0x802f)) {  //handling flashing command here to avoid de-sync
          if (!FlashingOn) {
            dataOut=0xffff;   //non togliere!!!
          } 
        }   
      } 
      else 
      {  //not jlp
      //  curBank=99;
          {

          for (int8_t i=0; i < slot; i++) {
            if (((parallelBus - maprom[i]) <= mapsize[i])){
              deviceAddress = true;     
              if (tipo[i]==2) {
                 dataOut=RAM[parallelBus-ramfrom];
                deviceAddress = true;
                break;
              }
              if (tipo[i]==0) {
                  dataOut=ROM[(parallelBus - mapdelta[i])];
                  break;
              }
              if (tipo[i]==1) {
                seg=(parallelBus>>12)&0xf;   
                if (page[i]==curPage[seg]) {
                  dataOut=ROM[(parallelBus - mapdelta[i])];
                  break;
                } else {dataOut=0xffff;}
              }
            } 
          }
        }
    
      } //if not jlp
        if (hacks>0) {
          for (int i=0; i<maxHacks;i++) {
            if (parallelBus==HACK[i]) {
              dataOut=HACK_CODE[i];
              deviceAddress = true;
	          }
            break;
          }
        } 
      }
      else
      {
         busBit >>= 1;
        if (!busBit)
        {
          // -----------------------
          // DWS WRITE
          // -----------------------
          SET_DATA_MODE_IN;

            if ((pagingOn)&&((parallelBus&0xfff)==0x0fff)) {
              if ((((dataWrite=gpio_get_all() & 0xffff) >> 4) & 0xff) == 0xA5) {
                seg=(parallelBus>>12)&0xf;   
                curPage[seg]=dataWrite & 0xf;
                curPage2=curPage[seg];
              }
            } //else // keep it!!
           if ((deviceAddress)) {
                //  asm inline ("nop;nop;nop;");
            dataWrite = gpio_get_all() & 0xFFFF; 
            if (((parallelBus>=0x8000)&&(parallelBus<=0x9fff))&& JLPOn) {
          //  if (((parallelBus>=0x8000)&&(parallelBus<=0x9fff))) {
              RAM[parallelBus-0x8000]=dataWrite;  
              if (parallelBus==0x9ffc) { // ha scritto 9ffc
                curCRC=RAM[0x1ffd];
                curCRC ^= RAM[0x1ffc];
                for (int i = 0; i < 16; i++) {
                  curCRC = (curCRC >> 1) ^ (curCRC & 1 ? 0xAD52 : 0);
                }
                RAM[0x1ffd]=curCRC;
                }
            } else
             { 
            if ((parallelBus>=ramfrom)&&(parallelBus<=ramto)) {
              if (RAM8) {
                RAM[parallelBus-ramfrom]=dataWrite & 0xFF;
              } else {
                RAM[parallelBus-ramfrom]=dataWrite;
              }
            } 
           }
          }
         else
        {
         // -----------------------
         // NACT, IAB, DW, INTAK
         // -----------------------
         // reconnect to bus
           SET_DATA_MODE_IN;
        }
        
        }
      } 
    }    
  }
} 

#pragma GCC pop_options


////////////////////////////////////////////////////////////////////////////////////
//                     Error(N)
////////////////////////////////////////////////////////////////////////////////////
void error(int numblink){
  Serial.print("Error ");
  Serial.println(numblink);
  while(1){
    gpio_set_dir(25,GPIO_OUT);
    
    for(int i=0;i<numblink;i++) {
      gpio_put(25,true);
      sleep_ms(600);
      gpio_put(25,false);
      sleep_ms(500);
      Serial.print("Error ");
      Serial.println(numblink);
    }
  sleep_ms(2000);
  }
}

/////////////////////////////////
// print on mfile on inty
////////////////////////////////
void printInty(char *temp) {
  for (int i=0;i<120;i++) RAM[0x17f+i]=0;
  for (int i=0;i<60;i++) {
    RAM[0x17f+i*2]=temp[i];
    if (temp[i]==0) {
      RAM[0x17f+i*2]='*';
      break;
    }
  }
  sleep_ms(1000);
} 
int read_directory(char *path) {
  //  if (path[0]==0) strcpy(path,'/');
    Serial.print("Read_directory: ");
    Serial.println(path);
    int ret = 0;
    num_dir_entries = 0;
    DIR_ENTRY *dst = (DIR_ENTRY *)&files[0];

    File dir=SD.open(path, O_RDONLY);
    if (dir) {
        File file;
        while (num_dir_entries < 90 && (file= dir.openNextFile())) {
            char filename[60];
            String(file.name()).toCharArray(filename,60);
            //Serial.println(filename);
            if (strcmp(filename, ".") == 0 || strcmp(filename, "..") == 0) {
                file.close();
                continue;
            }
            
            if ((strcmp(filename,"System Volume Information")==0) ||
            (strcmp(filename,"FOUND.000")==0))
            {
              // Serial.print(filename);Serial.println(" skipped!");
                file.close();
                continue;
            }
  
            dst->isDir = file.isDirectory();
            if (!dst->isDir && !is_valid_file(filename)) {
                file.close();
                continue;
            }
            
            // Usa lo stesso nome per entrambi i campi
            strncpy(dst->long_filename, filename, 31);
            dst->long_filename[31] = 0;
            strncpy(dst->filename, filename, 24);
            dst->filename[24] = 0;
            
            dst->full_path[0] = 0;
            dst++;
            num_dir_entries++;
            
            file.close();
        }
        dir.close();
        
        qsort((DIR_ENTRY *)&files[0], num_dir_entries, sizeof(DIR_ENTRY), entry_compare);
        ret = 1;
    }
    else {
        Serial.println("Can't read directory");
    }
    
    return ret;
}
/////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////* load file in  ROM */////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////

void load_file(char *filename) {
	
  int car_file = 0;
  int  size = 0;
	Serial.print("load file: ");
  Serial.println(filename);
  //printInty("loadfile");
  //printInty(filename);

 
	if (!(file=SD.open(filename))) {
		Serial.print("Can't open file ");
    Serial.println(filename);
    delay(2000);
    error(2);
	}

 Serial.println("Start load");
 size=0;
 while ((file.available()) && (size<(BINLENGTH-1))) {
  
    RBHi = file.read();
    RBLo = file.read();
   
    if (size<=(BINLENGTH-1)) ROM[size]= RBLo | (RBHi << 8);
   // if (size==0xbafd) Serial.print(size,HEX);Serial.print("-");Serial.println(ROM[size],HEX);
	  size++;
  }
  if (size>=(BINLENGTH-1)){ 
    Serial.println(size);
    Serial.println("Max size exceeded");
    /////while(1) {Serial.print("Error size ");}
    error(4);
  }
closefile:
  romLen=size;
  RAM[base+202]=romLen;
  Serial.print("Len: ");Serial.println(romLen);
  Serial.println("------start game!");
  file.close();
}
// Funzione per leggere una riga dal file

/////////////////////////////
bool leggiRiga(File &f, char* buf, int max) {
    int i = 0;
    while (i < max-1 && f.available()) {
        char c = f.read();
        if (c == '\n') break;
        if (c == '\r') {
            if (f.available() && f.peek() == '\n') f.read();
            break;
        }
        buf[i++] = c;
    }
    buf[i] = '\0';
    return i > 0 || f.available();
}




// Struttura per tenere insieme i dati correlati
typedef struct {
    unsigned int mapfrom;
    unsigned int mapto;
    unsigned int maprom;
    int mapdelta;  // Nota: nel tuo log è DEC, quindi signed
    unsigned int mapsize;
    unsigned int page;
    unsigned int tipo;
} SlotData;

// Funzione di confronto per qsort
int compareSlots(const void *a, const void *b) {
    SlotData *slotA = (SlotData *)a;
    SlotData *slotB = (SlotData *)b;
    
    // 1. Ordina per maprom (crescente)
    if (slotA->maprom < slotB->maprom) return -1;
    if (slotA->maprom > slotB->maprom) return 1;
    
    // 2. Se maprom è uguale, ordina per tipo (crescente)
    if (slotA->tipo < slotB->tipo) return -1;
    if (slotA->tipo > slotB->tipo) return 1;
    
    // 3. Se anche tipo è uguale, ordina per pagina (crescente)
    if (slotA->page < slotB->page) return -1;
    if (slotA->page > slotB->page) return 1;
    
    return 0; // Tutti i campi sono uguali
}



// Funzione di ordinamento con bubble sort (senza malloc)
void sortSlotsSimple(unsigned int mapfrom[], unsigned int mapto[], unsigned int maprom[], 
                     int mapdelta[], unsigned int mapsize[], unsigned int page[], 
                     unsigned int tipo[], int numSlots) {
    
    // Reset dei contatori
    Slot0 = 0;
    Slot1 = 0;
    
    // Conta gli slot per tipo prima dell'ordinamento
    for (int i = 0; i < numSlots; i++) {
        if (tipo[i] == 0) {
            Slot0++;
        } else if (tipo[i] == 1) {
            Slot1++;
        }
    }
    
    // Ordina gli array
    bool swapped;
    do {
        swapped = false;
        for (int i = 0; i < numSlots - 1; i++) {
            bool needSwap = false;
            
            // Confronta secondo i criteri: tipo, maprom, page
            if (tipo[i] > tipo[i + 1]) {
                needSwap = true;
            } else if (tipo[i] == tipo[i + 1]) {
                if (maprom[i] > maprom[i + 1]) {
                    needSwap = true;
                } else if (maprom[i] == maprom[i + 1]) {
                    if (page[i] > page[i + 1]) {
                        needSwap = true;
                    }
                }
            }
            
            // Scambia se necessario
            if (needSwap) {
                // Scambia tutti i valori
                unsigned int tempUint;
                int tempInt;
                
                // mapfrom
                tempUint = mapfrom[i];
                mapfrom[i] = mapfrom[i + 1];
                mapfrom[i + 1] = tempUint;
                
                // mapto
                tempUint = mapto[i];
                mapto[i] = mapto[i + 1];
                mapto[i + 1] = tempUint;
                
                // maprom
                tempUint = maprom[i];
                maprom[i] = maprom[i + 1];
                maprom[i + 1] = tempUint;
                
                // mapdelta
                tempInt = mapdelta[i];
                mapdelta[i] = mapdelta[i + 1];
                mapdelta[i + 1] = tempInt;
                
                // mapsize
                tempUint = mapsize[i];
                mapsize[i] = mapsize[i + 1];
                mapsize[i + 1] = tempUint;
                
                // page
                tempUint = page[i];
                page[i] = page[i + 1];
                page[i + 1] = tempUint;
                
                // tipo
                tempUint = tipo[i];
                tipo[i] = tipo[i + 1];
                tipo[i + 1] = tempUint;
                
                swapped = true;
            }
        }
    } while (swapped);
}
// Funzione per stampare i dati ordinati
// Funzione per stampare i dati ordinati
void printSortedSlots(unsigned int mapfrom[], unsigned int mapto[], unsigned int maprom[], 
                      int mapdelta[], unsigned int mapsize[], unsigned int page[], 
                      unsigned int tipo[], int numSlots) {
    for (int i = 0; i < numSlots; i++) {
        Serial.print("Slot No.:"); Serial.print(i); Serial.print(":"); 
        Serial.print(mapfrom[i], HEX); Serial.print("-");
        Serial.print(mapto[i], HEX); Serial.print("-");
        Serial.print(maprom[i], HEX); Serial.print("-");
        Serial.print(mapdelta[i], DEC); Serial.print("-");
        Serial.print(mapsize[i], HEX); Serial.print("-");
        Serial.print(page[i], HEX); Serial.print("-"); 
        Serial.println(tipo[i], HEX);
        if (tipo[i]==2) {
          Serial.print("Ram from:");Serial.print(ramfrom,HEX);
          Serial.print("Ram to:");Serial.println(ramto,HEX);
        }
    }
}

/////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////* load .cfg file */////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////

void load_cfg(char *filename) {
	int car_file = 0;
	int size = 0;
  unsigned char byteread=0;
  char riga[80];
  char tmp[80];
  int linepos,linepos2;     

  memset(tmp,0,sizeof(tmp));
  int j=40;
  int dot=0;
  while ((filename[j]!='.')&&(j>0)) {
    dot=j;
    j--;
  }
  for (int i=0;i<j;i++) tmp[i]=filename[i];
  tmp[j]=0;
   memcpy(flashFilename,tmp,sizeof(tmp));
   strcat(tmp,".cfg");
   memcpy(filename,tmp,sizeof(tmp));
   strcat(flashFilename,".jlp");
   Serial.print("Flash File:");Serial.println(flashFilename);
 

	if (!(file=SD.open(filename))) {
		Serial.println("cfg not found");
    //printInty("using 0.cfg");
    strcpy(filename,"/0.cfg");  
    if (!(file=SD.open(filename))) {
		  Serial.println("Can't find 0.cfg");
      error(3);
    }
  } else {
   Serial.println("cfg found");
  }
 
	unsigned char *dst = &byteread;
	int bytes_to_read = 1;
	// read the file to SRAM
    slot=0;  // poi rimettere dopo il debug!!! ------------------------------
  
  hacks=0;
  RAMused=0; 
  pagingOn=false;
  JLPOn=false;
  memset(segmentedPage,0,sizeof(segmentedPage));

  while (file.available()) {
    memset(riga,0,sizeof(riga));
    leggiRiga(file, riga, 79);
    //printInty(riga);
    if (riga[0]>=32) {
      //printInty("riga0>32");
      memset(tmp,0,sizeof(tmp));
      memcpy(tmp,riga,9);
      if ((!(strcmp(tmp,"jlp = 1")))||(!(strcmp(tmp,"jlp = 3")))) {
          JLPOn=true;
          initFlashFile();
      }
      if ((!(strcmp(tmp,"JLP = 1")))||(!(strcmp(tmp,"JLP = 3")))) {
                 JLPOn=true;
                 initFlashFile();
      }
      if (slot==0) {
        if (!(strcmp(tmp,"[mapping]"))) {
          memset(riga,0,sizeof(riga));
          leggiRiga(file, riga, 79);
          //printInty(riga);
         } else {
          Serial.println("[mapping] not found");
           error(4); // 3 error [mapping] section not found
        }
      }
      if (!(strcmp(tmp,"[memattr]"))) {
        memset(riga,0,sizeof(riga));
        leggiRiga(file, riga, 79);
        memset(tmp,0,sizeof(tmp)); 
        linepos=strcspn(riga,"-"); 
        memcpy(tmp,riga+1,linepos-1);
        ramfrom=strtoul(tmp,NULL,16);
        mapfrom[slot]=ramfrom;
        memset(tmp,0,sizeof(tmp));
        memcpy(tmp,riga+(linepos+3),5);
        ramto=strtoul(tmp,NULL,16);
        mapto[slot]=ramto; 
        maprom[slot]=ramfrom;
        addrto[slot]=maprom[slot]+(mapto[slot]-mapfrom[slot]);
        memset(tmp,0,sizeof(tmp));
        memcpy(tmp, riga + 20, 1);
        RAM8=false;
        tipo[slot]=2; // RAM
        slot++;
        if ((!strcmp(tmp,"8"))) {
          RAM8=true; // RAM8
          Serial.println("RAM 8");
        } else {
          Serial.println("RAM 16");
        }
        RAMused=1;
        mapdelta[slot]=maprom[slot] - mapfrom[slot]; //poi rimettere  --------------------------------
        mapsize[slot]=mapto[slot] - mapfrom[slot];  //poi rimettere  --------------------------------
        Serial.print("ram slot at: ");Serial.println(slot-1);
        leggiRiga(file, riga, 79);

        if (strcspn(riga,"$")>0) leggiRiga(file, riga, 79); //skip memattr slots after first
      } else {   
        memset(tmp,0,sizeof(tmp));
        memcpy(tmp,riga,1);
        if (!strcmp(tmp,"p")) {
          // [MACRO]
          memset(tmp,0,sizeof(tmp));
          memcpy(tmp,riga+2,4);
          HACK[hacks]=strtoul(tmp,NULL,16);
          memset(tmp,0,sizeof(tmp));
          memcpy(tmp,riga+7,4);
          HACK_CODE[hacks]=strtoul(tmp,NULL,16);
          hacks++;
        } else {
          //mapping
          linepos=strcspn(riga,"-");
          linepos2=strcspn(riga,"=");
          if ((linepos>=0) && (riga[linepos]=='-')) {
            //printInty("line>0");
            memset(tmp,0,sizeof(tmp));
            memcpy(tmp,riga+1,linepos-1);
            mapfrom[slot]=strtoul(tmp,NULL,16);  // poi rimettere --------------------------------
            if (linepos==6) {
              if (linepos2==14) {
                memset(tmp,0,sizeof(tmp));
                memcpy(tmp,riga+(linepos+3),4);
                mapto[slot]=strtoul(tmp,NULL,16);   
                memset(tmp,0,sizeof(tmp));
                memcpy(tmp,riga+(linepos+11),4);  
                maprom[slot]=strtoul(tmp,NULL,16);
              } else {
                memset(tmp,0,sizeof(tmp));
                memcpy(tmp,riga+(linepos+3),5);
                mapto[slot]=strtoul(tmp,NULL,16);  
                memset(tmp,0,sizeof(tmp));
                memcpy(tmp,riga+(linepos+12),5);  
                maprom[slot]=strtoul(tmp,NULL,16); 
              }
            } else { // linepos 7
              memset(tmp,0,sizeof(tmp));
              memcpy(tmp,riga+(linepos+3),5);
              mapto[slot]=strtoul(tmp,NULL,16); // poi rimettere --------------------------------
              if (linepos2==16) {
                memset(tmp,0,sizeof(tmp));
                memcpy(tmp,riga+(linepos+12),4);  
                maprom[slot]=strtoul(tmp,NULL,16);
                } else {
                  memset(tmp,0,sizeof(tmp));
                  memcpy(tmp,riga+(linepos+12),5);  
                  maprom[slot]=strtoul(tmp,NULL,16); 
                }
              }   
            addrto[slot]=maprom[slot]+(mapto[slot]-mapfrom[slot]); // poi rimettere ------------------
            linepos=strcspn(riga,"P");
            if ((linepos>0)&&(riga[linepos]!=0)) {
              tipo[slot]=1;   //poi rimettere -------------------------------- 
              pagingOn=true;
              segmentedPage[(maprom[slot]>>12)&0xf]=true;
              memset(tmp,0,sizeof(tmp));
              memcpy(tmp,riga+(linepos+5),2);
              page[slot]=strtoul(tmp,NULL,16); //poi rimettere  --------------------------------
         
            } else {
              segmentedPage[(maprom[slot]>>12)&0xf]=false;
              tipo[slot]=0;  // poi rimettere -------------------------
              page[slot]=0;
            } 
            slot++;
            //printInty("slot++");
          } 
        }
      }
      mapdelta[slot-1]=maprom[slot-1] - mapfrom[slot-1]; //poi rimettere  --------------------------------
      mapsize[slot-1]=mapto[slot-1] - mapfrom[slot-1];  //poi rimettere  --------------------------------
    }

    /*
    Serial.print("Slot No.:");Serial.print(slot-1);Serial.print(":"); 
    Serial.print(mapfrom[slot-1],HEX);Serial.print("-");
    Serial.print(mapto[slot-1],HEX);Serial.print("-");
    Serial.print(maprom[slot-1],HEX);Serial.print("-");
    Serial.print(mapdelta[slot-1],DEC);Serial.print("-");
    Serial.print(mapsize[slot-1],HEX);Serial.print("-");
    Serial.print(page[slot-1],HEX);;Serial.print("-"); 
    Serial.print(segmentedPage[slot-1],HEX);;Serial.print("-"); 
    Serial.println(tipo[slot-1],HEX); 
   */ 
  }
    if (RAMused) Serial.println("RAM used");
    if (JLPOn) Serial.println("JLP On");
    if (pagingOn) Serial.println("Paging On");
    

 // Al posto di sortSlots(), usa:
    sortSlotsSimple(mapfrom, mapto, maprom, mapdelta, mapsize, page, tipo, slot);
    Serial.println("\nDati ordinati per maprom, tipo, page:");
    printSortedSlots(mapfrom, mapto, maprom, mapdelta, mapsize, page, tipo, slot);
  
   // slot--;

closefile:
	file.close();
  Serial.print("Total slot No.:");Serial.println(slot); 


}


////////////////////////////////////////////////////////////////////////////////////
//                     filelist
////////////////////////////////////////////////////////////////////////////////////

void filelist(DIR_ENTRY* en,int da, int a)
{
  char longfilename[32];
  char tmp[32];

  int base=0x17f;
  for(int i=0;i<20*20;i++) RAM[base+i*2]=0;
    for(int n = 0;n<(a-da);n++) {
		memset(longfilename,0,32);
	
	 	if (en[n+da].isDir) {
			//strcpy(longfilename,"DIR->");
			RAM[0x1000+n]=1;
			strcat(longfilename, en[n+da].long_filename);
	 	} else {
			RAM[0x1000+n]=0;
			strcpy(longfilename, en[n+da].long_filename);
      /// rimuovo il .bin
      memset(tmp,0,sizeof(tmp));
      int j=32;
      int dot=0;
      while ((longfilename[j]!='.')&&(j>0)) {
      dot=j;
      j--;
      }
      for (int i=0;i<j;i++) tmp[i]=longfilename[i];
      tmp[j]=0;      
      memcpy(longfilename,tmp,sizeof(tmp));
	 	}
  
	 	for(int i=0;i<20;i++) {
      		RAM[base+i*2+(n*40)]=longfilename[i];
	  		if ((RAM[base+i*2+(n*40)])<=20) RAM[base+i*2+(n*40)]=32;
     	}
		strcpy((char*)&nomefiles[40*n], longfilename);
	}
	RAM[0x1030]=da;RAM[0x1031]=a;RAM[0x1032]=num_dir_entries;
  }



////////////////////////////////////////////////////////////////////////////////////
//                     IntyMenu
////////////////////////////////////////////////////////////////////////////////////
void IntyMenu(int tipo) { // 1=start,2=next page, 3=prev page, 4=dir up
  int numfile=0;
  int maxfile=0;
  int ret=0;
  int rootpos[255];
  int lastpos;
  	
  switch (tipo) {
    case 1:
    /////////////////// TIPO 1 /////////////////// 
      ret = read_directory(curPath);
		  if (!(ret)) {
        curPath[0]='/';
        curPath[1]=0;
        read_directory(curPath);
        Serial.println("Dir missed, return root");
        //error(1);
      }
		  maxfile=10;
		  fileda=0;
		  if (maxfile>num_dir_entries) maxfile=num_dir_entries;
		  filea=fileda+maxfile;
		  filelist((DIR_ENTRY *)&files[0],fileda,filea);
		  //sleep_ms(400);
      
      break;
    case 2:
    /////////////////// TIPO 2 /////////////////// 
   	  if (filea<num_dir_entries) {
        maxfile=10;
		    if ((filea+maxfile)>num_dir_entries) maxfile=num_dir_entries-filea;
   	    fileda=filea;
		    filea=fileda+maxfile;
    	  filelist((DIR_ENTRY *)&files[0],fileda,filea); 
      }
      break;
    case 3:    
    /////////////////// TIPO 3 /////////////////// 
   	  if (fileda>=10) {
  	    fileda=fileda-10;
		    filea=fileda+10;
		    filelist((DIR_ENTRY *)&files[0],fileda,filea);	
	    }
    break;
  }

}
////////////////////////////////////////////////////////////////////////////////////
//                     Directory Up
////////////////////////////////////////////////////////////////////////////////////
void DirUp() {
	int len = strlen(curPath);
	if (len>0) {
		while (len && curPath[--len] != '/');
		curPath[len] = 0;
	}
  if (len==0) curPath[0]='/';
}
////////////////////////////////////////////////////////////////////////////////////
// Inizializza File Flash
////////////////////////////////////////////////////////////////////////////////////
bool initFlashFile() {
    if (!SD.exists(flashFilename)) {
        Serial.print("Creating new flash file: ");
        Serial.println(flashFilename);
        
        File f = SD.open(flashFilename, O_WRONLY | O_CREAT);
        if (!f) {
            Serial.println("ERROR: Cannot create flash file!");
            return false;
        }
              // Creiamo un buffer di 0xFF per l'estensione
        uint8_t fillByte = 0xFF;
        for(uint32_t i = 0; i < 1024*32; i++) {
            f.write(fillByte);
        }
        
        f.close();
      //  eraseFlash(0);
        Serial.println("Flash file created successfully");
    } else {
        Serial.print("Flash file exists, size: ");
        File f = SD.open(flashFilename, O_RDONLY);
        Serial.print(f.size());
        Serial.println(" bytes");
        f.close();
    }
    return true;
}
////////////////////////////////////////////////////////////////////////////////////
// EraseFlash - VERSIONE CORRETTA
////////////////////////////////////////////////////////////////////////////////////
void eraseFlash(int row) {
    flashFile = SD.open(flashFilename, O_RDWR);
    if (!flashFile) {
        Serial.println("Error opening Flash in eraseFlash");
        return;
    }
    
    uint32_t fileOffset = row * 96 * 2;
    uint32_t requiredSize = fileOffset + (96 * 8 * 2);
    
    // ESTENSIONE DEL FILE CON APPROCCIO CORRETTO
    if (flashFile.size() < requiredSize) {
        // Troviamo la posizione corrente
        uint32_t currentPos = flashFile.position();
        
        // Andiamo ALLA FINE del file attuale
        flashFile.seek(flashFile.size());
        
        // Calcoliamo quanti byte mancano
        uint32_t bytesToExtend = requiredSize - flashFile.size();
        
        // Creiamo un buffer di 0xFF per l'estensione
        uint8_t fillByte = 0xFF;
        for(uint32_t i = 0; i < bytesToExtend; i++) {
            flashFile.write(fillByte);
        }
        
        // Torniamo alla posizione originale dove dobbiamo scrivere
        flashFile.seek(fileOffset);
    } else {
        flashFile.seek(fileOffset);
    }
    
    // Ora scriviamo i nostri 96 word (192 byte) di 0xFF
    uint8_t ff_byte = 0xFF;
    for (int i = 0; i < (192 ); i++) { // 96 * 2 = 192
        flashFile.write(ff_byte);
    }
    Serial.print("Erase->Flash File size:");Serial.println(flashFile.size(),DEC);
    flashFile.close();
    Serial.print("Erased flash row ");
    Serial.println(row);
}
////////////////////////////////////////////////////////////////////////////////////
// FillFlash - VERSIONE CORRETTA
////////////////////////////////////////////////////////////////////////////////////
void FillFlash(int row, int16_t addr) {
    flashFile = SD.open(flashFilename, O_RDWR | O_APPEND);
    if (!flashFile) {
        Serial.println("Error opening Flash in FillFlash ++++++++++++");
        return;
    }
    
    uint16_t ramBaseIdx = ((addr & 0xffff) - 0x8000);
    uint32_t fileOffset = row * 96 * 2;
    uint32_t requiredSize = fileOffset + (96 * 2);
    
    // STESSA LOGICA DI ESTENSIONE
    if (flashFile.size() < requiredSize) {
        uint32_t currentPos = flashFile.position();
        flashFile.seek(flashFile.size()-1);
        uint32_t bytesToExtend = requiredSize - flashFile.size();
        uint8_t zeroByte = 0xaa;
        Serial.println("Extend flash file");
        for(uint32_t i = 0; i < bytesToExtend; i++) {
            flashFile.write(zeroByte); // Estendi con zeri
        }
        flashFile.seek(fileOffset);
    } else {
        flashFile.seek(fileOffset);
    }
    
    // Scrivi i dati dalla RAM
    for (int i = 0; i < 96; i++) {
        flashFile.write((RAM[ramBaseIdx + i] >> 8) & 0xFF);   // High byte
        flashFile.write(RAM[ramBaseIdx + i] & 0xFF);          // Low byte
    }
    // Serial.print("Write->Flash File size:");Serial.println(flashFile.size(),DEC);
  
    flashFile.close();
    Serial.print("Filled flash row ");
    Serial.print(row);
    Serial.print(" from RAM addr 0x");
    Serial.println(ramBaseIdx, HEX);
}
////////////////////////////////////////////////////////////////////////////////////
// Read FLASH -> Write RAM
////////////////////////////////////////////////////////////////////////////////////
void FillRAM(int row, int16_t addr) {
    flashFile = SD.open(flashFilename, O_RDONLY);
    if (!flashFile) {
        Serial.println("Error opening Flash in FillRAM");
        return;
    }
    
    uint32_t fileOffset = row * 96 * 2;
    uint16_t ramAddr = addr & 0xFFFF;
    uint32_t ramStartIndex = (ramAddr - 0x8000);
   // Serial.print("Read->Flash File size:");Serial.println(flashFile.size(),DEC);
   // Serial.print(" offset: ");Serial.println(fileOffset);
   // Serial.print("Flash file size: ");Serial.println(flashFile.size());
    
    // Verifica che il file sia abbastanza grande
    if (flashFile.size() < (fileOffset + (96 * 2))) {
        Serial.print("Error: Flash file too small for row:");Serial.println(row);
      //  for (int i = 0; i < 96; i++) {RAM[ramStartIndex + i] = 0xff;}
     //   flashFile.close();
        //eraseFlash(row);
     //   return;
    }
    
    flashFile.seek(fileOffset);
    
    for (int i = 0; i < 96; i++) {
        uint8_t highByte = flashFile.read();
        uint8_t lowByte = flashFile.read();
        RAM[ramStartIndex + i] = (highByte << 8) | lowByte;
    }
    
    flashFile.close();
    // Serial.println("RAM filled");
}

#pragma GCC push_options
#pragma GCC optimize ("O0")
////////////////////////////////////////////////////////////////////////////////////
//                     LOAD Game
////////////////////////////////////////////////////////////////////////////////////

void LoadGame(){ 
  int numfile=0;
  int numErr=0;
  char longfilename[32];
  char firstbyte=0x0;

   numfile=RAM[0x899]+fileda-1;
   
   DIR_ENTRY *entry = (DIR_ENTRY *)&files[0];
   strcpy(longfilename,entry[numfile].long_filename);
  
  if (entry[numfile].isDir)
	{	// directory
    strcat(curPath, "/");
		strcat(curPath, entry[numfile].filename);
		IntyMenu(1);
	} else {
		memset(path,0,sizeof(path));
		strcat(path,curPath);
		strcat(path, "/");
		strcat(path,longfilename);
    
    char savepath[256];
    memcpy(savepath,path,sizeof(path)); // preserve path
  	load_cfg(path);
    
    
    load_file(savepath);  // load rom in files[]
    //delay(100);
    gpio_put(LED_PIN,false);
   	//memset(RAM,0,sizeof(RAM));
    for(int i=0x8000;i<sizeof(RAM);i++) RAM[i]=0;

    sleep_ms(200);
    resetCart(); // inizia con il gioco!
    sleep_ms(200);
    resetCart(); // inizia con il gioco!
    gameloaded=true;

 
    RAM[0x1ffc]=0;
    RAM[0x1ffd]=0;
    RAM[0x1fff]=0;
    RAM[0x1f8e]=0;
    RAM[0x0023]=0x0; // starting free flash row
    RAM[0x0024]=0x60; // last free flash row
    RAM[0x0025]=0x0; // row to operate
    RAM[0x0026]=0x0; // ram addr to operate
    RAM[0x002d]=0x0;
    RAM[0x002e]=0x0;
    RAM[0x002f]=0x0;
    
    RAM[0x1ffe]=random(0,0x10000);        
    if (romLen>=210000) {
      vreg_set_voltage(VREG_VOLTAGE_1_30);
      set_sys_clock_khz(400000, true);
      Serial.println("++ set ovclk to TURBO");
    } else {
      vreg_set_voltage(VREG_VOLTAGE_1_25);
      set_sys_clock_khz(360000, true);
      Serial.println("++ set ovclk to Faster");
    }
    delayMicroseconds(30);
    Serial.println("Game loop");
    
    uint16_t value=0;

    
/* ============================================================================= */
/*  JLP_SG_RAM_TO_FLASH     -- Copy 96 words from JLP RAM to Flash               */
/*  JLP_SG_FLASH_TO_RAM     -- Copy 96 words (192 byte) from Flash to JLP RAM    */
/*  JLP_SG_ERASE_SECTOR     -- Erase a 768 word (1536 char) flash sector to $FFFF*/
/* ============================================================================= */
    FlashingOn=false; 
    uint8_t prevCP=1;
    uint8_t prevCB=17;
    bool startrace=false;
    uint16_t curCRC;
    uint16_t pbc = parallelBus2;
        int tracecount=0;
  
    while(1) {
      pbc = parallelBus2;
    
      if (JLPOn) { 
         
        if ((pbc >= 0x802d) && (pbc < 0x8040)) {
            
          switch(pbc) {
/*         
            case 0x8023: // $802D JF.wrcmd Write­only Copy JLP RAM to flash. Must write the value $C0DE.
                  RAM[0x23] = 0x0;
              break;
              
            case 0x8024: // $802D JF.wrcmd Write­only Copy JLP RAM to flash. Must write the value $C0DE.
                  RAM[0x24] = 0x60;
              break;
*/              
            case 0x802D: // $802D JF.wrcmd Write­only Copy JLP RAM to flash. Must write the value $C0DE.
              {
                if (RAM[0x2d] == 0xC0DE) {
                  RAM[0x2d] = 0xffff;
                  FillFlash(RAM[0x26], RAM[0x25]);
                  Serial.print("JLP fill row: ");Serial.print(RAM[0x26]);Serial.print(" from RAM ->");Serial.println(RAM[0x25],HEX); 
                  RAM[0x2d] = 0x0;
                 
                  FlashingOn = true;   
              }
            }
              break;
            case 0x802E: // $802E JF.rdcmd Write­only Copy flash to JLP RAM. Must write the value $DEC0.
              {
               if (RAM[0x2e] == 0xDEC0) {
                 RAM[0x2e]=0xffff; 
                  FillRAM(RAM[0x26],RAM[0x25]); 
                  Serial.print("JLP read row: ");Serial.print(RAM[0x26]);Serial.print(" to RAM ->");Serial.println(RAM[0x25],HEX); //EraseSector();
                   RAM[0x2e]=0x0; 
                  FlashingOn=true;      
                }  
              }
              break;
            case 0x802F: // $802F JF.ercmd Write­only Erase flash sector. Must write the value $BEEF.
              {
               if (RAM[0x2F] == 0xBEEF) {  
                  RAM[0x2F] = 0xffff;
                  //eraseFlash(RAM[0x26]); 
                  Serial.print("JLP EraseSector ->");Serial.println(RAM[0x26],HEX); //EraseSector();
                   RAM[0x2F] = 0x0;
                  FlashingOn=true;   
                }
              }
              break;  
            case 0x8034: // $8034 switch off JLP
              {
               if (RAM[0x34] == 0x6a7a) {  
                  //eraseFlash(RAM[0x26]); 
                  Serial.print("JLP OFF");
                   JLPOn=false;   
                }
              }
              break;  
           case 0x8033: // $8033 switch on JLP
              {
               if (RAM[0x33] == 0x4a5a) {  
                  //eraseFlash(RAM[0x26]); 
                  Serial.print("JLP On");
                   JLPOn=true;   
                }
              }
              break;  
 
            default:
                    // Altri indirizzi nell'intervallo 0x8000-0x8023 non gestiti
                    Serial.print("hit 0x");Serial.println(pbc,HEX);
                    break;
            }
        } else {
        if ((pbc >= 0x9f80) && (pbc < 0x9fff)) {
            switch(pbc) {
                case 0x9f80:
                case 0x9f81:
                    {
                        int16_t op1 = RAM[0x1F80];
                        int16_t op2 = RAM[0x1F81];
                        int32_t res = op1 * op2;
                        RAM[0x1f8f] = (res) >> 16;
                        RAM[0x1f8e] = (res & 0xffff);
                        //Serial.print("multiply:");
                        //Serial.println(RAM[0x1f8e],HEX);
                    }
                    break;
                case 0x9f82:
                case 0x9f83:
                    {
                        int16_t op1 = RAM[0x1F82];
                        uint16_t op2 = RAM[0x1F83];
                        int32_t res = op1 * op2;
                        RAM[0x1f8f] = (res & 0xffff0000) >> 16;
                        RAM[0x1f8e] = (res & 0xffff);
                    }
                    break;
                case 0x9f84:
                case 0x9f85:
                    {
                        uint16_t op1 = RAM[0x1F84];
                        int16_t op2 = RAM[0x1F85];
                        int32_t res = op1 * op2;
                        RAM[0x1f8f] = (res & 0xffff0000) >> 16;
                        RAM[0x1f8e] = (res & 0xffff);
                    }
                    break;
                case 0x9f86:
                case 0x9f87:
                    {
                        uint16_t op1 = RAM[0x1F86];
                        uint16_t op2 = RAM[0x1F87];
                        int32_t res = op1 * op2;
                        RAM[0x1f8f] = (res & 0xffff0000) >> 16;
                        RAM[0x1f8e] = (res & 0xffff);
                    }
                    break;
                case 0x9f88:
                case 0x9f89:
                    {
                        int16_t op1 = RAM[0x1F88];
                        int16_t op2 = RAM[0x1F89];
                        int16_t res = op1 % op2;
                        RAM[0x1f8f] = res;
                        res = op1 / op2;
                        RAM[0x1f8e] = res;
                    }
                    break;
                case 0x9f8a:
                case 0x9f8b:
                    {
                        uint16_t op1 = RAM[0x1F8a];
                        uint16_t op2 = RAM[0x1F8b];
                        int16_t res = op1 % op2;
                        RAM[0x1f8f] = res;
                        res = op1 / op2;
                        RAM[0x1f8e] = res;
                    }
                    break;
                /*
                case 0x9ffc:  //crc 16
                  {
                  curCRC=RAM[0x1ffd];
                  curCRC ^= RAM[0x1ffc];
                    for (int i = 0; i < 16; i++) {
                      curCRC = (curCRC >> 1) ^ (curCRC & 1 ? 0xAD52 : 0);
                    }
                  RAM[0x1ffd]=curCRC;
                  }
                    break;
               case 0x9ffd:
                   //     Serial.print("C:");Serial.println(RAM[0x1ffd],HEX);                        // delay(2);
                    break;
                */

                case 0x9ffe:
                    RAM[0x1ffe] = random(0, 0x10000);
                    //Serial.print("Rnd:");Serial.println(RAM[0x1ffe],HEX);
                    break;

                default:
                    // Altri indirizzi nell'intervallo 0x9f80-0x9fff non gestiti
                    break;
            }
        }
      }
  /*
    //  if (((pbc==0x7715)||(startrace))&( tracecount<100))
      if (((pbc==0x8a12)||(startrace))&( tracecount<100))
      {
        Serial.print(pbc,HEX);Serial.print("-");
        Serial.println(ROM[pbc],HEX);
        startrace=true;
        tracecount++;
      } 
      
       
       if ((prevCB != curBank)&&(curBank<99)){
          prevCB=curBank;
          Serial.print("Bus:0x");Serial.print(pbc,HEX);
          Serial.print("-Bank:");Serial.println(curBank);
       } 

      if (prevCP != curPage2){
          Serial.print("Bus:0x");Serial.print(pbc,HEX);
          Serial.print("-Page:");Serial.println(curPage2);
          prevCP=curPage2;
      } 
      */
      
    } else { // end jlp on 
        
        gpio_put(LED_PIN, true);
        sleep_ms(2000);
        gpio_put(LED_PIN, false);
        sleep_ms(2000);
        Serial.print(".");
      
    }
  } // end while
 }
}

////////////////////////////////////////////////////////////////////////////////////
//                     SETUP
////////////////////////////////////////////////////////////////////////////////////

void setup() {
  
  gpio_init_mask(ALWAYS_IN_MASK|ALWAYS_OUT_MASK);
  pinMode(MSYNC_PIN,INPUT_PULLDOWN);
  pinMode(RST_PIN,OUTPUT);
  
  bool carton=false;
 // reset interval in ms
   int t = 100;

   while (gpio_get(MSYNC_PIN) == 0 && to_ms_since_boot(get_absolute_time()) < 2000) {   // wait for Inty powerup
      if (to_ms_since_boot(get_absolute_time()) > t) {
         t += 100;
         gpio_put(RST_PIN, false);
         sleep_ms(5);
         gpio_put(RST_PIN, true);
      }
   }

  Serial.begin(115200);
  while ((!Serial)&&(to_ms_since_boot(get_absolute_time())) < 200);   // wait for native usb
  
    SPI.setRX(SD_MISO);
    SPI.setTX(SD_MOSI);
    SPI.setSCK(SD_SCK);
    bool sdInitialized = SD.begin(SD_CS);
  if (!sdInitialized) {
    Serial.println("SD initialization failed!");
    error(1);
  }
  Serial.println("SD initialization done.");


}

////////////////////////////////////////////////////////////////////////////////////
//                     MAIN LOOP
////////////////////////////////////////////////////////////////////////////////////    
  
void loop1()
{
     
}


////////////////////////////////////////////////////////////////////////////////////
//                     Inty Cart Main
////////////////////////////////////////////////////////////////////////////////////

void loop()
{
    uint32_t pins;
    uint32_t addr;
    uint32_t dataOut=0;
    uint16_t dataWrite=0;
 
  Serial.println("Loop");

	// overclocking isn't necessary for most functions - but XEGS carts weren't working without it
	// I guess we might as well have it on all the time.
  vreg_set_voltage(VREG_VOLTAGE_1_20);
  set_sys_clock_khz(270000, true);
 
  //multicore_launch_core1(core1_main);

  // Initialize the bus state variables
  // Inty bus values (BC1+BC2+BDIR) GPIO 18-17-16
  // Inty bus values (BC1+BC2+BDIR) GPIO 26-27-22
  busLookup[BUS_NACT]  = 4; // 100
  busLookup[BUS_BAR]   = 1; // 001
  busLookup[BUS_IAB]   = 4; // 100
  busLookup[BUS_DWS]   = 2; // 010   // test without dws handling
  busLookup[BUS_ADAR]  = 1; // 001
  busLookup[BUS_DW]    = 4; // 100
  busLookup[BUS_DTB]   = 0; // 000
  busLookup[BUS_INTAK] = 4; // 100


  gpio_init_mask(ALWAYS_OUT_MASK||ALWAYS_IN_MASK);
  gpio_init_mask(DATA_PIN_MASK);
  gpio_init_mask(BUS_STATE_MASK);
  gpio_set_dir_in_masked(ALWAYS_IN_MASK);
  gpio_set_dir_out_masked(ALWAYS_OUT_MASK);
  gpio_init(LED_PIN);
  gpio_put(LED_PIN,true); 
  gpio_init(RST_PIN);
  
  gpio_set_dir(MSYNC_PIN,GPIO_IN);
  gpio_pull_down(MSYNC_PIN);
  
  sleep_ms(800);
#ifdef intidebug
  RAM[0x163]=2; //1 for debug, 2 for debug with looping
#endif

  resetHigh(); 
  sleep_ms(30);
  resetLow();
  //while (gpio_get(MSYNC_PIN)==1); // wait for Inty powerup
  Serial.println("Inty Pow-ON");
  
  gpio_put(LED_PIN,true);
  memset(ROM,0,BINLENGTH);
  
  for (int i=0;i<(sizeof(_acpirtoIIDuo)/2);i++) {
   ROM[i]=_acpirtoIIDuo[(i*2)+1] | (_acpirtoIIDuo[i*2] << 8);
  }
  //memset(RAM,0,sizeof(RAM));
  //for(int i=0;i<sizeof(RAM);i++) RAM[i]=0;;
  
 for (int i=0; i<maxHacks; i++) {
  HACK[i]=0;
  HACK_CODE[i]=0;
 }

  slot=2; // 2 slots per splash

  //  [mapping]
  //$0000 - $0dFF = $5000
  mapfrom[0]=0x0;
  mapto[0]=0xdff;
  maprom[0]=0x5000;
  tipo[0]=0;
  page[0]=0;
  addrto[0]=0x5dff;
  mapdelta[0]=maprom[0] - mapfrom[0];
  mapsize[0]=mapto[0] - mapfrom[0];
    
 //[memattr]
 //$8000 - $9FFF = RAM 16
  RAMused=1;
  ramfrom=0x8000;
  ramto=0x9fff;
  mapfrom[1]=0x8000;
  mapto[1]=0x9fff;
  maprom[1]=0x8000;
  tipo[1]=2;
  page[1]=0;
  addrto[1]=0x9fff;
  mapdelta[1]=maprom[1] - mapfrom[1];
  mapsize[1]=mapto[1] - mapfrom[1];
  
  //sleep_ms(200);
  //resetCart();
  sleep_ms(200);
  resetCart();
  sleep_ms(1200);
  // Initial conditions 
  memset(curPath,0,sizeof(curPath));
  curPath[0]='/';
  Serial.print("Curpath:");
  Serial.println(curPath);
  sleep_ms(800);
	
  RAM[0x889]=0;
  sleep_ms(800);
	RAM[0x119]=1;
   	 
  RAM[0x119]=123;
   gpio_put(LED_PIN,true);
  
  
  IntyMenu(1);
  
  while (1) {
     cmd_executing=false;
     cmd=RAM[0x889];
     RAM[0x119]=0;
 
     if ((cmd>0)&&!(cmd_executing)) {
      switch (cmd) {
      case 1:  // read file list
        cmd_executing=true;
        RAM[0x889]=0;
    	  IntyMenu(1);
	 	    RAM[0x119]=1;
      	sleep_ms(600);
        Serial.print("new path:");Serial.println(curPath);
      	break;
      case 2:  // run file list
        cmd_executing=true;
    	  RAM[0x889]=0;
	 	    LoadGame();
		    RAM[0x119]=1;
      	sleep_ms(600);
      	break;
      case 3:  // next page
	      cmd_executing=true;
        RAM[0x889]=0;
        IntyMenu(2);
		    RAM[0x119]=1;
        Serial.println("next page");
        sleep_ms(600);
      	break;
      case 4:  // prev page
        cmd_executing=true;
        RAM[0x889]=0; 
     	  IntyMenu(3);
		    RAM[0x119]=1;
        Serial.println("prev page");
        sleep_ms(600);
	 	    break;
	    case 5:  // up dir
        cmd_executing=true;
        RAM[0x889]=0; 
     	  DirUp();
		    IntyMenu(1);
		    RAM[0x119]=1;
        sleep_ms(600);
        Serial.print("Dirup->new path:");Serial.println(curPath);
	 	    break;
    }     
   }
  }
}
#pragma GCC pop_options 	