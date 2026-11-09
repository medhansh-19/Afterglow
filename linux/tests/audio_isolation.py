"""Verify selected-stream capture with two simultaneous real PulseAudio sources."""
import array,json,math,os,signal,subprocess,threading,time

def run(*args):return subprocess.check_output(args,text=True).strip()
# Use an existing PipeWire-Pulse/PulseAudio server before starting a test server.
# PipeWire systems commonly install the clients without the pulseaudio daemon.
if subprocess.run(['pactl','info'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode:
    subprocess.run(['pulseaudio','--start','--exit-idle-time=-1'],check=True)
module=run('pactl','load-module','module-null-sink','sink_name=afterglow_fixture','rate=48000','channels=2')
children=[];running=True
try:
    def play(name,frequency):
        process=subprocess.Popen(['pacat','--playback','--device=afterglow_fixture','--raw','--format=float32le','--rate=48000','--channels=2',f'--property=application.name={name}'],stdin=subprocess.PIPE,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        children.append(process)
        def write():
            phase=0
            try:
                while running:
                    samples=array.array('f')
                    for i in range(2048):
                        value=.2*math.sin(2*math.pi*frequency*(phase+i)/48000);samples.extend([value,value])
                    phase+=2048;process.stdin.write(samples.tobytes());process.stdin.flush()
            except (BrokenPipeError,ValueError):pass
        threading.Thread(target=write,daemon=True).start()
    play('AfterglowFixtureA',1000);play('AfterglowFixtureB',4000)
    streams=[]
    for _ in range(50):
        streams=json.loads(run('pactl','--format=json','list','sink-inputs'))
        if len([s for s in streams if s['properties'].get('application.name','').startswith('AfterglowFixture')])==2:break
        time.sleep(.1)
    selected=next(s for s in streams if s['properties'].get('application.name')=='AfterglowFixtureA')
    capture=subprocess.Popen(['parec',f"--monitor-stream={selected['index']}",'--device=afterglow_fixture.monitor','--raw','--format=float32le','--rate=48000','--channels=2','--latency-msec=50'],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    children.append(capture)
    signal.alarm(15)
    raw=capture.stdout.read(48000*8)
    signal.alarm(0)
    samples=array.array('f');samples.frombytes(raw);mono=samples[::2]
    assert len(mono)>=24000,'No selected-stream audio was captured'
    # Skip initial scheduling silence; spectral projection distinguishes the two known sources.
    mono=mono[len(mono)//2:]
    def amplitude(freq):
        r=sum(x*math.cos(2*math.pi*freq*i/48000) for i,x in enumerate(mono));im=sum(x*math.sin(2*math.pi*freq*i/48000) for i,x in enumerate(mono));return 2*math.hypot(r,im)/len(mono)
    selected_level=amplitude(1000);other_level=amplitude(4000)
    assert selected_level>.1,(selected_level,other_level)
    assert other_level<selected_level*.01,(selected_level,other_level)
    print(f'PASS selected-stream isolation: selected={selected_level:.5f}, other={other_level:.7f}')
finally:
    running=False
    for process in children:
        process.terminate()
    for process in children:
        try:process.wait(timeout=3)
        except subprocess.TimeoutExpired:process.kill();process.wait()
        if process.stdin:
            try:process.stdin.close()
            except BrokenPipeError:pass
    subprocess.run(['pactl','unload-module',module],check=True)
