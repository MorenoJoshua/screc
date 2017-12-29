//
//  main.cpp
//  screc
//
//  Created by Max Fomichev on 11/11/15.
//  Copyright © 2015 Pieci Kvadrati. All rights reserved.
//
#include <time.h>
#include <signal.h>
#include <getopt.h>
#include <sys/types.h>
#include <sys/stat.h>

#include <thread>
#include <mutex>
#include <iostream>
#include <sstream>
#include <iomanip>

#include "wrapper.hpp"

static std::mutex exitCondLock;
static bool exitCond = false;

//signal handler thread
void signalHandler() {
    int sign = 0;
    sigset_t sigs;
    
    sigemptyset(&sigs);
    sigaddset(&sigs, SIGINT); //exit
    sigaddset(&sigs, SIGHUP); //exit
    sigaddset(&sigs, SIGQUIT); //exit
    sigaddset(&sigs, SIGTERM); //exit
    sigprocmask(SIG_BLOCK, &sigs, NULL);
    
    signal(SIGPIPE, SIG_IGN);
    
    while (true) {
        sigwait(&sigs, &sign);
        
        switch (sign) {
            case SIGINT:
            case SIGHUP:
            case SIGQUIT:
            case SIGTERM: {
//                std::cout<<"Signal received: "<<sign<<std::endl;
                std::lock_guard<std::mutex> locker(exitCondLock);
                exitCond = true;
                return;
            } default: {
                continue;
            }
        }
    }
}

static void usage(const char *_name)
{
    std::cout
        << _name << " [options]" << std::endl
        << "Options:" << std::endl
            << "  -d, --display <id>\t\tset active display to <id>" << std::endl
                << "\t\t\t\t\tfrom 0 up to 7" << std::endl
            << "  -r, --resolution <val>\tset output video to <val>:" << std::endl
                << "\t\t\t\t\t1 - 320x240" << std::endl
                << "\t\t\t\t\t2 - 352x288" << std::endl
                << "\t\t\t\t\t3 - 640x480" << std::endl
                << "\t\t\t\t\t4 - 960x540" << std::endl
                << "\t\t\t\t\t5 - 1280x720" << std::endl
            << "  -f, --fps <count>\t\tset frames per second rate to <count>," << std::endl
                << "\t\t\t\t\tfrom 1 up to 30" << std::endl
            << "  -s, --font <size>\t\tset timestamp label font size" << std::endl
                << "\t\t\t\t\tfrom 10 up to 100" << std::endl
            << "  -p, --path <path>\t\twrite output files to <path>" << std::endl
            << "  -h, --help\t\t\tprint usage information" << std::endl;
}

static struct option longopts[] = {
    {"display",     required_argument,  NULL,   'd' },
    {"resolution",  required_argument,  NULL,   'r' },
    {"fps",         required_argument,  NULL,   'f' },
    {"font",        required_argument,  NULL,   's' },
    {"path",        required_argument,  NULL,   'p' },
    {"help",        no_argument,        NULL,   'h' },
    {NULL,          0,                  NULL,   0 }
};

class recorder_t {
private:
    void *m_objectInstance;
    uint8_t m_screen;
    screenResolution_t m_screenResolution;
    uint8_t m_frameRate;
    uint8_t m_fontSize;
    std::string m_fileName;

    recorder_t() {;}
    
public:
    recorder_t(uint8_t _screen, screenResolution_t _screenResolution,
               uint8_t _frameRate, uint8_t _fontSize, const std::string &_fileName):
        m_objectInstance(nullptr), m_screen(_screen), m_screenResolution(_screenResolution),
        m_frameRate(_frameRate), m_fontSize(_fontSize), m_fileName(_fileName) {
    }
    
    ~recorder_t() {
        if (m_objectInstance != nullptr)
            stop(m_objectInstance);
    }
    
    bool launch() {
        m_objectInstance = start(m_screen, m_screenResolution, m_frameRate,
                                 m_fontSize, m_fileName.c_str());
        if (m_objectInstance == nullptr)
            return false;
        
        return true;
    }
};

int main(int argc, char * const *argv) {
    
    int dsp = 0;
    int res = 0;
    int fps = 0;
    int fontSize = 0;
    std::string basePath;
    
    int ch;
    while ((ch = getopt_long(argc, argv, "d:r:f:s:p:h", longopts, NULL)) != -1) {
        switch (ch) {
            case 'd': {
                dsp = atoi(optarg);
                if ((dsp < 0) || (dsp >= 8)) {
//                    std::cerr << "Wrong resolution value, must be between 1 and 5" << std::endl;
                    return 1;
                }
                break;
            } case 'r': {
                res = atoi(optarg);
                if ((res < 1) || (res > 5)) {
//                    std::cerr << "Wrong resolution value, must be between 1 and 5" << std::endl;
                    return 1;
                }
                break;
            } case 'f': {
                fps = atoi(optarg);
                if ((fps < 1) || (fps > 30)) {
//                    std::cerr << "Wrong FPS value, must be between 1 and 30" << std::endl;
                    return 1;
                }
                break;
            } case 's': {
                fontSize = atoi(optarg);
                if ((fontSize < 10) || (fontSize > 100)) {
//                    std::cerr << "Wrong FPS value, must be between 1 and 30" << std::endl;
                    return 1;
                }
                break;
            } case 'p': {
                struct stat pathStat;
                stat(optarg, &pathStat);
                if (!(pathStat.st_mode & S_IFDIR)) {
//                    std::cerr << optarg << " is not a directory" << std::endl;
                    return 1;
                }

                basePath = optarg;
                
                break;
            } case 'h':
            case ':':
            case '?':
                usage(argv[0]);
                return 1;
            default:
                usage(argv[0]);
                return 1;
        }
    }
    if (((dsp < 0) || (dsp >= 8)) || ((res < 1) || (res > 5)) || ((fps < 1) || (fps > 30)) ||
            ((fontSize < 10) || (fontSize > 100)) || (basePath.length() == 0)) {
        usage(argv[0]);
        return 1;
    }

    std::thread signalHandlerThread(signalHandler);
    signalHandlerThread.detach();

    int curMDay = -1;
    int curHour = -1;
    std::string dayPath;
    std::string fileName;
    recorder_t *recorder = nullptr;
    while (true) {
        time_t curTime = time(NULL);
        struct tm *curTimeTM = localtime(&curTime);
        
        if (curMDay != curTimeTM->tm_mday) {
            std::stringstream tmpStream;
            tmpStream<<basePath << "/" << curTimeTM->tm_year + 1900 << "."
                      << std::setw(2) << std::setfill('0') << curTimeTM->tm_mon + 1 << "."
                     << std::setw(2) << std::setfill('0') << curTimeTM->tm_mday;
            dayPath = tmpStream.str();
#warning Make suru that 0777 is not dangerous
            if ((mkdir(dayPath.c_str(), 0777) != 0) && (errno != EEXIST)) {
//                std::cerr << "Can not create directory " << dayPath << std::endl;
                return 2;
            }
            if (chmod(dayPath.c_str(), 0777) != 0) {
                return 2;
            }
            curMDay = curTimeTM->tm_mday;
        }
        
        if (curHour != curTimeTM->tm_hour) {
            std::stringstream tmpStream;
            tmpStream<<dayPath<<"/"<<std::setw(2)<<std::setfill('0')<<curTimeTM->tm_hour<<"."
                     <<std::setw(2)<<std::setfill('0')<<curTimeTM->tm_min<<"."
                     <<std::setw(2)<<std::setfill('0')<<curTimeTM->tm_sec<<".mp4";
            fileName = tmpStream.str();

            delete recorder;
            recorder = new recorder_t(dsp, (screenResolution_t) res, (uint8_t) fps, (uint8_t) fontSize, fileName);
            if (!recorder->launch())
                return 2;

            curHour = curTimeTM->tm_hour;
        }

        sleep(1);

        std::lock_guard<std::mutex> locker(exitCondLock);
        if (exitCond) {
            delete recorder;
            return 0;
        }
    }
    
    return 0;
}
